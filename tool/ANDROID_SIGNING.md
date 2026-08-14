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

Run this yourself — it prompts for passwords, which is why it is not scripted
here. `keytool` ships with the JDK bundled in Android Studio:

```
"C:\Program Files\Android\Android Studio\jbr\bin\keytool" -genkey -v ^
  -keystore %USERPROFILE%\tali-release.jks ^
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 ^
  -alias tali
```

`-validity 10000` (about 27 years) is the usual choice: Play requires the key to
outlast the app, and there is no way to rotate it afterwards.

Then create `android/key.properties`, which the Gradle build reads:

```
storeFile=C:\\Users\\<you>\\tali-release.jks
storePassword=<the store password you chose>
keyAlias=tali
keyPassword=<the key password you chose>
```

Backslashes must be doubled — it is a Java properties file.

## Verifying a build is properly signed

`key.properties` missing is not an error: the build falls back to the debug key
and prints a warning, so a fresh clone still builds. That means a release APK
can be debug-signed without anything obviously going wrong, and it is worth
checking rather than assuming:

```
flutter build apk --release --split-per-abi
"%LOCALAPPDATA%\Android\Sdk\build-tools\37.0.0\apksigner" verify --print-certs ^
  build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
```

A debug-signed build shows `CN=Android Debug, O=Android, C=US`. Your own
certificate's details mean the real key was used.

## Which artifact to build

- **Play Store**: `flutter build appbundle --release`. Play splits per-device
  from the bundle, so users download only their ABI.
- **Sideloading / GitHub release**: `flutter build apk --release --split-per-abi`.
  A universal APK carries every ABI's copy of libmpv and is roughly twice the
  size of the one a given phone actually needs.
