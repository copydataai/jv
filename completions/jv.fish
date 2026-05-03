complete -c jv -f
complete -c jv -n "__fish_use_subcommand" -a "create init explain doctor history events retry watch compile run remember forget clean help version"
complete -c jv -n "__fish_use_subcommand" -l help -s h
complete -c jv -n "__fish_use_subcommand" -l version -s v
complete -c jv -n "__fish_seen_subcommand_from history events" -l limit
complete -c jv -n "__fish_seen_subcommand_from history events" -l failures
complete -c jv -n "__fish_seen_subcommand_from history events retry doctor" -l json
complete -c jv -n "__fish_seen_subcommand_from retry" -l dry-run
complete -c jv -n "__fish_seen_subcommand_from remember forget" -a "main"
