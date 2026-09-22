# Example

`deploy.yaml` in this directory is what `deploykit init` generates.

To use it:

```bash
cd your_flutter_app
dart pub global activate deploykit
deploykit init
cp .env.example .env     # then fill in the values
deploykit doctor --dev
deploykit publish --dev --dry-run
```
