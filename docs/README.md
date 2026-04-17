# Documentation

| Doc | Contents |
|-----|----------|
| [CLI reference](cli-reference.md) | Subcommands, flags, operations, overlay mapping |
| [apple-apis.csv](apple-apis.csv) | All Apple developer framework URLs + names, parsed from the navbar |
| [subcommands/](subcommands/) | Per-subcommand API surface and operation listings |

---

## apple-apis.csv — parser

**Script:** `docs/parse_apple_navbar.py`
**Input:** `docs/apple-navbar-docs.html` (gitignored — must be sourced manually)
**Output:** `docs/apple-apis.csv`

### How to regenerate

```
python3 docs/parse_apple_navbar.py
```

### How to get the input HTML

1. Open `https://developer.apple.com/documentation/` in a browser.
2. Wait for the left-hand framework navigator to fully render (it is JS-driven via Vue).
3. Inspect the navigator panel, copy the outer HTML of the `.vue-recycle-scroller__item-wrapper` element, and save it to `docs/apple-navbar-docs.html`.

### HTML structure the parser targets

The navigator renders each framework as a `.navigator-card-item` div. Inside each item:

```html
<a class="leaf-link" href="/documentation/<Framework>?language=objc">
  <p class="highlight">Framework Display Name</p>
</a>
```

The parser:
- Matches every `<a href="/documentation/...">` anchor (ignoring query strings).
- Extracts the path component and prepends `https://developer.apple.com`.
- Reads the inner text of the sibling `<p class="highlight">` as the API name.
- Deduplicates by URL, sorts alphabetically by name, and writes `url,name` CSV rows.
