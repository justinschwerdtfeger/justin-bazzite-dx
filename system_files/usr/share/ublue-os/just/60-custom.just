# Choose the shell for your Niri session: dms, noctalia, or none.
[group('Niri')]
niri-shell $shell:
    #!/usr/bin/bash
    exec /usr/libexec/niri-shell-switch "$shell"
