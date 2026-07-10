ALB 0.3.0 manual package

Package contents:
- ALB.dll
- ALBCore.dll
- ALBLoader.ini
- alb-config.default.json
- RELEASE-NOTES.md

Install:
1. Copy the package files into the EuroScope ALB plugin folder.
2. Configure EuroScope to load ALB.dll.
3. Keep any existing alb-config.json in place.

Config safety:
- Do not overwrite a live alb-config.json with alb-config.default.json.
- If you need a fresh starting template, copy alb-config.default.json to
  alb-config.json manually and review the values before operational use.

Autoupdate behavior:
- This package's ALBLoader.ini is production-style.
- The loader may update ALBCore.dll and alb-config.default.json only.
- The loader must not update ALB.dll.
- The loader must not overwrite alb-config.json.
