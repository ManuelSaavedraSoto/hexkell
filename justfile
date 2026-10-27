# Generate tree diagram of project structure
tree:
    @echo $'# Tree\n\nTree diagram of project structure\n\n```bash' > ./docs/TREE.md
    @tree --gitignore --dirsfirst --noreport -I 'addons|*.uid|*.import' . >> ./docs/TREE.md
    @echo '```' >> ./docs/TREE.md