# Infrastructure & Deployment Design

## GitHub Pages Web Deployment Strategy
CRITICAL: The live website is hosted on GitHub Pages via the `gh-pages` branch. It does NOT serve directly from `main`.

Whenever you are asked to "push to github" or "deploy", pushing to `main` is ONLY for source code backup. It WILL NOT update the live website.

To update the live web application, you MUST execute the exact following sequence:
1. Run `flutter build web` to compile the Dart source into the web assets.
2. Run `powershell -ExecutionPolicy Bypass -File deploy.ps1` to run the local cache-busting script, which clones and commits the build to the local `gh-pages` branch.
3. Run `git push origin gh-pages` to push the compiled website to GitHub Actions for live deployment.

Failure to follow this procedure will result in the live website serving outdated code.
