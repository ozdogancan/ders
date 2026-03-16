p = 'android/app/build.gradle.kts'
with open(p, 'r', encoding='utf-8') as f:
    c = f.read()

# Add keystore properties loading at top
old1 = 'android {\n    namespace = "com.egitim_ai_tutor.app"\n    compileSdk = flutter.compileSdkVersion'

new1 = '''import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.egitim_ai_tutor.app"
    compileSdk = flutter.compileSdkVersion'''

if old1 in c:
    c = c.replace(old1, new1, 1)
    print("PATCH 1 OK: Added keystore properties loading")
else:
    print("PATCH 1 SKIP")

# Replace release signing config
old2 = '''    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }'''

new2 = '''    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }'''

if old2 in c:
    c = c.replace(old2, new2, 1)
    print("PATCH 2 OK: Added release signing config")
else:
    print("PATCH 2 SKIP")

with open(p, 'w', encoding='utf-8') as f:
    f.write(c)

print("Done!")
