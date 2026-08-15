# Android release signing

Release builds are signed with a key you create and keep. Nothing in this
document should ever be committed: `android/key.properties`, `*.jks` and
`*.keystore` are gitignored.

## Why it matters

The keystore is the app's identity on Android, not just a formality:

- **Lose it** and you can never publish an update. Android refuses to install a
  new version signed with a different key over an existing install, and Play
  ties the listing to the key. The only route back is a new listing under a new
  application ID, abandoning every existing user.
- **Leak it** and anyone can sign builds that phones will accept as genuine
  updates to your app.
- A **debug-signed** APK has the same trap in miniature: whoever installs it
  cannot later upgrade to a properly signed build without uninstalling first,
  losing their playlists and watch history in the process.

Back the `.jks` up somewhere private and durable. A password manager or an
encrypted backup is appropriate; a git repository is not.

## Creating the keystore

Commands here are PowerShell. Run this yourself in an **interactive** terminal:
`keytool` prompts for the passwords and for your name and organisation, so it
cannot be scripted or run through anything non-interactive. The JDK bundled
with Android Studio provides it.

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkey -v `
  -keystore "$env:USERPROFILE\tali-release.jks" `
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 `
  -alias tali
```

Two PowerShell details that bite here. The leading `&` is required: a quoted
string on its own is just a string, and without the call operator PowerShell
prints the path instead of running it. And the line continuation is a backtick,
not `^` — copying the `cmd` form silently runs `keytool` with no arguments,
which drops you into its usage text rather than an error.

`-validity 10000` (about 27 years) is the usual choice: Play requires the key to
outlast the app, and there is no way to rotate it afterwards.

Then create `android/key.properties`, which the Gradle build reads:

```properties
storeFile=C:/Users/<you>/tali-release.jks
storePassword=<the store password you chose>
keyAlias=tali
keyPassword=<the key password you chose>
```

Forward slashes on purpose. This is a Java properties file, where a backslash
is an escape character, so a Windows path either needs every separator doubled
(`C:\\Users\\...`) or written with forward slashes — which Gradle's `file()`
accepts on Windows, and which nobody gets wrong.

## Verifying a build is properly signed

`key.properties` missing is not an error: the build falls back to the debug key
and prints a warning, so a fresh clone still builds. That means a release APK
can be debug-signed without anything obviously going wrong, and it is worth
checking rather than assuming:

```powershell
flutter build apk --release --split-per-abi

# apksigner is a .bat that shells out to java, and it will not find one on its
# own - without JAVA_HOME it fails with "Unable to locate a Java Runtime".
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"

# Pick the newest build-tools rather than pinning a version that may not be
# the one installed.
$apksigner = Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\build-tools\*\apksigner.bat" |
    Sort-Object FullName | Select-Object -Last 1

& $apksigner.FullName verify --print-certs `
  build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
```

A debug-signed build shows `CN=Android Debug, O=Android, C=US`. Your own
certificate's details mean the real key was used.

Note that `flutter build` prints the "no android/key.properties" warning among a
great deal of Gradle output and does not fail, so reading the certificate is the
only reliable check. Do this before sending an APK to anyone.

## Which artifact to build

- **Play Store**: `flutter build appbundle --release`. Play splits per-device
  from the bundle, so users download only their ABI.
- **Sideloading / GitHub release**: `flutter build apk --release --split-per-abi`.
  A universal APK carries every ABI's copy of libmpv and is roughly twice the
  size of the one a given phone actually needs.
