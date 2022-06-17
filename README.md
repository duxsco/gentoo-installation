# Gentoo Linux Installation

The documentation can be found in the `docs/` folder. To run the site locally do:

1. Install as `root`:

```
echo "dev-python/mkdocs ~amd64
dev-python/mkdocs-material ~amd64" >> /etc/portage/package.accept_keywords/main

emerge -av dev-python/mkdocs dev-python/mkdocs-material
```

2. Install [mkdocs-enumerate-headings-plugin](https://github.com/timvink/mkdocs-enumerate-headings-plugin)

3. Within the folder containing `mkdocs.yml`, execute as `non-root`:

```bash
mkdocs serve
```
