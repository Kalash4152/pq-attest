"""
PQ-Attest v1
KMAC128 Reference Implementation

Based on:
    - Keccak-f[1600]
    - SP 800-185 cSHAKE128
    - SP 800-185 KMAC128

Project-specific KDF:
    K = KMAC128(
            key = ROOT_SECRET,
            message =
                encode_string(TILE_ID)
                || encode_string(EPOCH)
                || encode_string(CONTEXT),
            customization = b"",
            output_bytes = 16 or 32
        )

Supported v1 derived-key sizes:
    16 bytes = 128 bits
    32 bytes = 256 bits
"""

from keccak_ref import create_state, keccak_f1600


# ============================================================
# Constants
# ============================================================

RATE_BYTES = 168
OUTPUT_BYTES = 32


# ============================================================
# SP 800-185 Encoding Functions
# ============================================================

def left_encode(x):
    """
    SP 800-185 left_encode(x).

    Returns:
        byte-length || big-endian(x)
    """

    if x < 0:
        raise ValueError("left_encode input must be non-negative")

    n = max(1, (x.bit_length() + 7) // 8)

    return bytes([n]) + x.to_bytes(n, "big")


def right_encode(x):
    """
    SP 800-185 right_encode(x).

    Returns:
        big-endian(x) || byte-length
    """

    if x < 0:
        raise ValueError("right_encode input must be non-negative")

    n = max(1, (x.bit_length() + 7) // 8)

    return x.to_bytes(n, "big") + bytes([n])


def encode_string(s):
    """
    SP 800-185 encode_string(S).

    Encodes a byte string as:

        left_encode(len(S) * 8) || S
    """

    bit_length = len(s) * 8

    return (
        left_encode(bit_length)
        + s
    )


def bytepad(x, w):
    """
    SP 800-185 bytepad(X, w).

    Produces a byte string whose length is a multiple of w.
    """

    if w <= 0:
        raise ValueError(
            "bytepad width must be positive"
        )

    z = left_encode(w) + x

    z += bytes(
        (-len(z)) % w
    )

    return z


# ============================================================
# cSHAKE Encoding
# ============================================================

def encode_name_customization(
    function_name,
    customization
):
    """
    Encode cSHAKE function-name and customization strings.
    """

    return (
        encode_string(function_name)
        + encode_string(customization)
    )


def cshake_prefix(
    function_name,
    customization
):
    """
    Construct the cSHAKE bytepad prefix.
    """

    encoded = encode_name_customization(
        function_name,
        customization
    )

    return bytepad(
        encoded,
        RATE_BYTES
    )


# ============================================================
# Byte Utilities
# ============================================================

def xor_bytes(a, b):
    """
    XOR two equal-length byte strings.
    """

    if len(a) != len(b):
        raise ValueError(
            "xor_bytes inputs must have equal length"
        )

    return bytes(
        x ^ y
        for x, y in zip(a, b)
    )


# ============================================================
# Keccak Sponge
# ============================================================

def keccak_sponge(
    data,
    rate_bytes,
    domain_suffix,
    output_bytes
):
    """
    Generic Keccak sponge.

    Parameters:
        data          : input byte string
        rate_bytes    : sponge rate in bytes
        domain_suffix : domain-separation byte
        output_bytes  : requested output length
    """

    if rate_bytes <= 0:
        raise ValueError(
            "rate_bytes must be positive"
        )

    if output_bytes < 0:
        raise ValueError(
            "output_bytes must be non-negative"
        )

    # --------------------------------------------------------
    # Domain separation and padding
    # --------------------------------------------------------

    padded = bytearray(data)

    padded.append(domain_suffix)

    while len(padded) % rate_bytes != 0:
        padded.append(0)

    # Multi-rate padding final bit
    padded[-1] |= 0x80

    # --------------------------------------------------------
    # Initialize Keccak state
    # --------------------------------------------------------

    state = create_state()

    # --------------------------------------------------------
    # Absorb
    # --------------------------------------------------------

    for offset in range(
        0,
        len(padded),
        rate_bytes
    ):

        block = padded[
            offset:
            offset + rate_bytes
        ]

        # Rate consists of 64-bit lanes
        for i in range(rate_bytes // 8):

            lane = int.from_bytes(
                block[
                    i * 8:
                    (i + 1) * 8
                ],
                "little"
            )

            x = i % 5
            y = i // 5

            state[x][y] ^= lane

        state = keccak_f1600(state)

    # --------------------------------------------------------
    # Squeeze
    # --------------------------------------------------------

    output = bytearray()

    while len(output) < output_bytes:

        for i in range(rate_bytes // 8):

            x = i % 5
            y = i // 5

            output.extend(
                state[x][y].to_bytes(
                    8,
                    "little"
                )
            )

            if len(output) >= output_bytes:
                break

        if len(output) < output_bytes:

            state = keccak_f1600(state)

    return bytes(
        output[:output_bytes]
    )


# ============================================================
# cSHAKE128
# ============================================================

def cshake128(
    message,
    output_bytes,
    function_name=b"",
    customization=b""
):
    """
    SP 800-185 cSHAKE128.

    If both function_name and customization are empty,
    this reduces to SHAKE128.
    """

    # --------------------------------------------------------
    # SHAKE128 case
    # --------------------------------------------------------

    if (
        function_name == b""
        and customization == b""
    ):

        return keccak_sponge(
            message,
            RATE_BYTES,
            0x1F,
            output_bytes
        )

    # --------------------------------------------------------
    # cSHAKE case
    # --------------------------------------------------------

    prefix = bytepad(
        encode_name_customization(
            function_name,
            customization
        ),
        RATE_BYTES
    )

    data = prefix + message

    return keccak_sponge(
        data,
        RATE_BYTES,
        0x04,
        output_bytes
    )


# ============================================================
# KMAC128
# ============================================================

def kmac128(
    key,
    message,
    output_bytes,
    customization=b""
):
    """
    SP 800-185 KMAC128.

    Construction:

        KMAC128(K, X, L, S)
        =
        cSHAKE128(
            bytepad(encode_string(K), 168)
            || X
            || right_encode(L),
            L,
            "KMAC",
            S
        )
    """

    if output_bytes < 0:
        raise ValueError(
            "output_bytes must be non-negative"
        )

    # --------------------------------------------------------
    # Output length in bits
    # --------------------------------------------------------

    output_bits = output_bytes * 8

    # --------------------------------------------------------
    # Encode and bytepad key
    # --------------------------------------------------------

    key_block = bytepad(
        encode_string(key),
        RATE_BYTES
    )

    # --------------------------------------------------------
    # Construct KMAC input
    # --------------------------------------------------------

    data = (
        key_block
        + message
        + right_encode(output_bits)
    )

    # --------------------------------------------------------
    # KMAC uses cSHAKE with:
    #
    # Function name = "KMAC"
    # Customization = S
    # --------------------------------------------------------

    return cshake128(
        data,
        output_bytes,
        function_name=b"KMAC",
        customization=customization
    )


# ============================================================
# PQ-Attest v1 Tile-Key KDF
# ============================================================

def derive_tile_key(root_secret, tile_id, epoch, context, key_bytes=16):
    """
    PQ-Attest KMAC-based per-tile KDF reference.

    root_secret : provisioned secret key
    tile_id     : tile identifier as bytes
    epoch       : epoch identifier as bytes
    context     : protocol/domain context as bytes
    key_bytes   : derived key length in bytes
    """

    if key_bytes not in (16, 32):
        raise ValueError(
            "PQ-Attest v1 supports only "
            "16-byte or 32-byte keys"
        )

    kdf_message = (
        encode_string(tile_id)
        + encode_string(epoch)
        + encode_string(context)
    )

    return kmac128(
        key=root_secret,
        message=kdf_message,
        output_bytes=key_bytes,
        customization=b""
    )


# ============================================================
# KMAC128 NIST Known-Answer Test
# ============================================================

if __name__ == "__main__":

    # --------------------------------------------------------
    # NIST SP 800-185 KMAC128 example
    # --------------------------------------------------------

    key = bytes.fromhex(
        "404142434445464748494a4b4c4d4e4f"
        "505152535455565758595a5b5c5d5e5f"
    )

    message = bytes.fromhex(
        "00010203"
    )

    expected = (
        "e5780b0d3ea6f7d3a429c5706aa43a00"
        "fadbd7d49628839e3187243f456ee14e"
    )

    actual = kmac128(
        key=key,
        message=message,
        output_bytes=32,
        customization=b""
    ).hex()

    print("PQ-Attest KMAC128 Reference")
    print("=" * 60)

    print(f"Expected : {expected}")
    print(f"Actual   : {actual}")

    if actual == expected:
        print("KMAC128 KAT: PASS")
    else:
        print("KMAC128 KAT: FAIL")
        raise SystemExit(1)