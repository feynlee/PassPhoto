# PassPhoto

iPhone app that fits a photo to passport, visa and ID photo rules: it measures the head on-device,
crops with scaling only, checks quality with Private Cloud Compute, and saves to Photos or the app.

## Requirements data

The requirements come from the public repository
[feynlee/passphoto-requirements](https://github.com/feynlee/passphoto-requirements), which is re-checked
against official sources every quarter. The app bundles a copy in `PassPhoto/Requirements/` and
downloads newer versions itself (`RequirementsUpdater`), verifying each file's SHA-256 against the
manifest. Before a release, refresh the bundled copy:

    cp ../passphoto-requirements/requirements/*.json ../passphoto-requirements/SCHEMA.md PassPhoto/Requirements/

## Debugging

Launch with `-demoEditor` (debug builds only) to open the editor on a drawn portrait with preset measurements.
