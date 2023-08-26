# Gentoo Linux Installation

```
  _______________________________________________
/ This repo has been archived!                    \
| Its successor is at:                            |
\ https://codeberg.org/duxsco/gentoo-installation /
  -----------------------------------------------
         \   ^__^
          \  (oo)\_______
             (__)\       )\/\
                 ||----w |
                 ||     ||
```

The documentation can be found in the "docs/" folder. To run the site locally do:

1. Install as "root":

```shell
echo "dev-python/mkdocs ~amd64
dev-python/mkdocs-material-extensions ~amd64
dev-python/mkdocs-minify-plugin ~amd64
dev-python/mkdocs-material ~amd64" >> /etc/portage/package.accept_keywords/main

emerge -av dev-python/mkdocs dev-python/mkdocs-material dev-python/mkdocs-minify-plugin
```

2. Within the folder containing "mkdocs.yml", execute as "non-root":

```shell
mkdocs serve
```

## Other Gentoo Linux repos

https://github.com/duxsco?tab=repositories&q=gentoo-
