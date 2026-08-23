# Codespaces bootstrap

After extracting the project into the repository root:

```bash
java -version
# must report JDK 17 for the Gradle/JVM target

gradle --version
# Gradle 9.5.0 is required by AGP 9.3.0

# If Gradle is not installed in the image, install/use Gradle 9.5.0.
gradle assembleDebug
```

Build all three apps:

```bash
gradle :system:assembleDebug :blockade:assembleDebug :metrics:assembleDebug
```

Then APKs are under:

```text
system/build/outputs/apk/debug/system-debug.apk
blockade/build/outputs/apk/debug/blockade-debug.apk
metrics/build/outputs/apk/debug/metrics-debug.apk
```
