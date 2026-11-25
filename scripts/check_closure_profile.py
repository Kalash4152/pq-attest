"""Read-only qualification of the new profile; never rewrites reference artifacts."""
import sys
import gen_closure_profile
if __name__=='__main__':
    sys.argv=[sys.argv[0],'--check']
    gen_closure_profile.main()
