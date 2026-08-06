# Git

Copy `.gitconfig` to `~/.gitconfig`. Back up an existing one first:

```bash
cp ~/.gitconfig ~/.gitconfig.bak 2>/dev/null
cp git/.gitconfig ~/.gitconfig
```

Sets `user.name`, `user.email`, `init.defaultBranch=main`, and
`pull.rebase=true`.
