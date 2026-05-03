_jv_completions() {
    local cur prev commands history_flags top_flags
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    commands="create init explain doctor history events retry watch compile run remember forget clean help version"
    history_flags="--limit --failures --json"
    top_flags="--help -h --version -v"

    if [[ $COMP_CWORD -eq 1 ]]; then
        mapfile -t COMPREPLY < <(compgen -W "$commands $top_flags" -- "$cur")
        return 0
    fi

    case "${COMP_WORDS[1]}" in
        history|events)
            mapfile -t COMPREPLY < <(compgen -W "$history_flags" -- "$cur")
            ;;
        retry)
            mapfile -t COMPREPLY < <(compgen -W "--dry-run --json" -- "$cur")
            ;;
        doctor)
            mapfile -t COMPREPLY < <(compgen -W "--json" -- "$cur")
            ;;
        remember|forget)
            [[ "$prev" == "${COMP_WORDS[1]}" ]] && mapfile -t COMPREPLY < <(compgen -W "main" -- "$cur")
            ;;
    esac
}

complete -F _jv_completions jv
