# Crunch Cartel POS identity

Created with the built-in `image_gen` tool from the user's gold brush-lettering and crowned-burger reference.

- `crunch-cartel-wordmark.png`: transparent two-line gold wordmark for full navigation and sign-in.
- `crunch-cartel-icon.png`: opaque square crowned-burger mark for compact navigation and the Windows application icon.

The Windows workflow converts the square PNG into an ICO containing 16, 24, 32, 48, 64, 128 and 256 pixel images, then applies the app window title and product name. Conversion and executable generation run only in GitHub Actions. The executable filename and existing database location stay compatible with earlier packages.

## Wordmark prompt

```text
Use case: logo-brand. Create a production transparent-background PNG wordmark asset for the restaurant POS, closely inspired by the attached reference. Text VERBATIM: CRUNCH on first line, CARTEL on second line. Only those two words, spelled correctly. Gold painted brush lettering with energetic confident forward slant, rich warm gold and pale gold highlights like the reference, strong clean letter silhouettes readable at small UI size. Tight rectangular composition approx 2.5:1 width/height, both lines centered, fill canvas with small 4% transparent padding. Isolate WORDMARK ONLY: no burger, no crown, no wall, no sign, no mockup, no background, no tagline, no extra flourishes or scattered specks. Gold lettering must have real alpha transparency around it. This asset will appear next to a separate burger mark in a compact desktop app sidebar.
```

## Icon prompt

```text
Use case logo-brand. Create a final Windows desktop application icon for Crunch Cartel restaurant POS inspired by the attached reference's crowned burger. Single square 1024x1024 icon. Deep near-black navy solid background #101820 across full square; centered warm gold #E9B959 crowned burger line-art emblem, confident thick clean rounded strokes, three-layer burger with sesame top bun and simple zigzag cheese, three-to-five-point crown directly above burger. Emblem occupies 78% of canvas, generous even safety margin. Gold strokes approximately 5% of canvas width so recognizable at 16px and 32px. Use flat smooth vector-like shapes and minimal detail. No lettering, no words, no initials, no tagline, no gradients, no glow, no metallic texture, no wall, no mockup, no additional decoration. The symbol should read as premium fast-food gold crown plus burger and match the reference silhouette. Full square opaque background, no rounded outer corners.
```
