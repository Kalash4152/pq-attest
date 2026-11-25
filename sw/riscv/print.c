/* ============================================================
 * print.c — SW5, minimal UART print library
 * No printf, no newlib — three hand-written functions only,
 * per the freestanding coding standard.
 *
 * Assumes Person A's uart_tx.sv 16-entry FIFO semantics:
 * status bit0 = busy means "FIFO full", not "mid-character",
 * so this should rarely block. >>> PERSON-A DATA <<< — confirm
 * this busy/FIFO interpretation with them before trusting the
 * polling-overhead numbers in Step 9 (traffic generator); if
 * busy actually means something stricter, this loop spins more
 * than expected and your measurement-hygiene subtraction (SW8)
 * needs to account for it.
 * ============================================================ */

#include "print.h"
#include "../MEMORY_MAP.h"

#define REG32(addr) (*(volatile uint32_t *)(addr))

static void uart_putc(char c)
{
    /* Wait while busy (bit0 of status register) */
    while (REG32(UART_REG_STATUS) & 0x1u) { /* spin */ }
    REG32(UART_REG_DATA) = (uint32_t)(uint8_t)c;
}

void print_str(const char *s)
{
    while (*s) {
        if (*s == '\n') uart_putc('\r'); /* CRLF for terminal sanity */
        uart_putc(*s++);
    }
}

void print_hex(uint32_t v)
{
    static const char digits[] = "0123456789ABCDEF";
    print_str("0x");
    for (int shift = 28; shift >= 0; shift -= 4) {
        uart_putc(digits[(v >> shift) & 0xF]);
    }
}

void print_int(int32_t v)
{
    char buf[12]; /* enough for -2147483648 + NUL */
    int i = 0;
    uint32_t u;

    if (v < 0) {
        uart_putc('-');
        u = (uint32_t)(-(int64_t)v); /* avoid INT32_MIN overflow */
    } else {
        u = (uint32_t)v;
    }

    if (u == 0) {
        uart_putc('0');
        return;
    }

    while (u > 0) {
        buf[i++] = (char)('0' + (u % 10));
        u /= 10;
    }
    while (i > 0) {
        uart_putc(buf[--i]);
    }
}
