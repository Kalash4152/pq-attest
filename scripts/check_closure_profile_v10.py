"""Read-only profile-10 qualification; never changes reference artifacts."""
import sys
import gen_closure_profile_v10
if __name__=='__main__':
    sys.argv=[sys.argv[0],'--check']
    gen_closure_profile_v10.main()
