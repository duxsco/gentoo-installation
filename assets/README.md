`Gentoo Linux amd64 Handbook.txt` created with:

```bash
curl --proto '=https' --tlsv1.3 https://wiki.gentoo.org/wiki/Handbook:AMD64/Full/Installation | html2text -utf8 -width 9999 | cat -v | sed -e 's/\(.\)\^H\(.\)/\2/g' -e 's/\(.\)\^H\(.\)/\2/g' > Gentoo\ Linux\ amd64\ Handbook.txt
```
