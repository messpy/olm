# olm
- shell command output helper
- run command and explain output
- analyze stdin text
- keep history
- config via ~/.config/olm/config.env

# install
- ./setup.sh
- source ~/.profile
- olm --help

# config
- copy config/config.env.example to ~/.config/olm/config.env
- set OLM_MODEL_STD OLM_MODEL_LGT OLM_MODEL_HVY OLM_MODEL_FA OLM_MODEL_FB
- set OLM_LANG
- set OLM_ALWAYS_PROMPT

# usage
- olm "ls -la"
- journalctl -u ssh -n 200 | olm --analyze
- olmhistory --last 20
