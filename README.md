# olm
- shell command helper
- run command and explain output
- analyze text from stdin
- keep history as tsv
- config via ~/.config/olm/config.env

# install
- ./setup.sh
- source ~/.profile
- olm --help

# config
- if ~/.config/olm/config.env does not exist it will be created from config/config.env.example
- key examples
- OLM_MODEL_STD
- OLM_MODEL_LGT
- OLM_MODEL_HVY
- OLM_MODEL_FA
- OLM_MODEL_FB
- OLM_LANG
- OLM_ALWAYS_PROMPT

# usage
- olm "ls -la"
- olm -e "ls /nope"
- echo "some log text" | olm --analyze
- printf "%s\n" "pwd" "ls -la" | olm --exec-stdin --yes
- olm config list
- olm config set OLM_LANG jp
- olm history --last 50
