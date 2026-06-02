import java.io.File
import java.util.Locale
import java.util.Properties
import org.gradle.api.DefaultTask
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Copy
import org.gradle.api.tasks.Exec
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.TaskAction

abstract class ValidateReleaseSigningTask : DefaultTask() {
  @get:Input abstract val signingConfigured: Property<Boolean>
  @get:Input abstract val keystorePath: Property<String>

  @TaskAction
  fun validate() {
    if (!signingConfigured.get()) {
      error(
        "Release signing is required. Set ANDROID_RELEASE_KEYSTORE, " +
          "ANDROID_RELEASE_KEYSTORE_PASSWORD, ANDROID_RELEASE_KEY_ALIAS, and " +
          "ANDROID_RELEASE_KEY_PASSWORD, or pass the matching clipdock.release* Gradle properties."
      )
    }

    val keystoreFile = File(keystorePath.get())
    if (!keystoreFile.isFile) {
      error("Release keystore not found: ${keystoreFile.absolutePath}")
    }
  }
}

plugins {
  alias(libs.plugins.android.application)
  alias(libs.plugins.compose.compiler)
  alias(libs.plugins.kotlin.serialization)
}

val releaseMetadataFile = rootProject.file("../version.properties")
val releaseProperties =
  Properties().apply {
    if (!releaseMetadataFile.isFile) {
      error("Release metadata not found: ${releaseMetadataFile.absolutePath}")
    }
    releaseMetadataFile.inputStream().use(::load)
  }

fun releaseProperty(key: String): String =
  releaseProperties.getProperty(key)?.trim()?.takeIf { it.isNotEmpty() }
    ?: error("Missing $key in ${releaseMetadataFile.absolutePath}")

val releaseVersionName = releaseProperty("VERSION_NAME")
val releaseVersionCode =
  releaseProperty("VERSION_CODE").toIntOrNull()
    ?: error("VERSION_CODE must be an integer in ${releaseMetadataFile.absolutePath}")

fun releaseSigningValue(propertyName: String, environmentName: String): String? =
  providers.gradleProperty(propertyName)
    .orElse(providers.environmentVariable(environmentName))
    .orNull
    ?.trim()
    ?.takeIf { it.isNotEmpty() }

val releaseKeystorePath =
  releaseSigningValue("clipdock.releaseKeystore", "ANDROID_RELEASE_KEYSTORE")
val releaseKeystorePassword =
  releaseSigningValue("clipdock.releaseKeystorePassword", "ANDROID_RELEASE_KEYSTORE_PASSWORD")
val releaseKeyAlias =
  releaseSigningValue("clipdock.releaseKeyAlias", "ANDROID_RELEASE_KEY_ALIAS")
val releaseKeyPassword =
  releaseSigningValue("clipdock.releaseKeyPassword", "ANDROID_RELEASE_KEY_PASSWORD")
val releaseSigningConfigured =
  listOf(releaseKeystorePath, releaseKeystorePassword, releaseKeyAlias, releaseKeyPassword)
    .all { !it.isNullOrEmpty() }
val releaseKeystoreAbsolutePath = releaseKeystorePath?.let { file(it).absolutePath }

android {
    namespace = "com.apkdv.clipdock"
    compileSdk = 36
    ndkVersion = "27.3.13750724"
    defaultConfig {
        applicationId = "com.apkdv.clipdock"
        minSdk = 26
        targetSdk = 36
        versionCode = releaseVersionCode
        versionName = releaseVersionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk {
          abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    signingConfigs {
      if (releaseSigningConfigured) {
        create("release") {
          storeFile = file(releaseKeystorePath!!)
          storePassword = releaseKeystorePassword
          keyAlias = releaseKeyAlias
          keyPassword = releaseKeyPassword
        }
      }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            if (releaseSigningConfigured) {
              signingConfig = signingConfigs.getByName("release")
            }
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
      compose = true
      aidl = false
      buildConfig = false
      shaders = false
    }

    packaging {
      resources {
        excludes += "/META-INF/{AL2.0,LGPL2.1}"
      }
    }

    sourceSets {
      getByName("main") {
        jniLibs.setSrcDirs(listOf(layout.buildDirectory.dir("generated/rustJniLibs").get().asFile))
      }
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
  val composeBom = platform(libs.androidx.compose.bom)
  implementation(composeBom)
  androidTestImplementation(composeBom)

  // Core Android dependencies
  implementation(libs.androidx.core.ktx)
  implementation(libs.androidx.lifecycle.runtime.ktx)
  implementation(libs.androidx.activity.compose)

  // Arch Components
  implementation(libs.androidx.lifecycle.runtime.compose)
  implementation(libs.androidx.lifecycle.viewmodel.compose)

  // Compose
  implementation(libs.androidx.compose.ui)
  implementation(libs.androidx.compose.ui.tooling.preview)
  implementation(libs.androidx.compose.material3)
  // Tooling
  debugImplementation(libs.androidx.compose.ui.tooling)
  // Instrumented tests
  androidTestImplementation(libs.androidx.compose.ui.test.junit4)
  debugImplementation(libs.androidx.compose.ui.test.manifest)

  // Local tests: jUnit, coroutines, Android runner
  testImplementation(libs.junit)
  testImplementation(libs.kotlinx.coroutines.test)
  testImplementation("org.json:json:20180813")

  // Instrumented tests: jUnit rules and runners
  androidTestImplementation(libs.androidx.test.core)
  androidTestImplementation(libs.androidx.test.ext.junit)
  androidTestImplementation(libs.androidx.test.runner)
  androidTestImplementation(libs.androidx.test.espresso.core)

  // Navigation
  implementation(libs.androidx.navigation3.ui)
  implementation(libs.androidx.navigation3.runtime)
  implementation(libs.androidx.lifecycle.viewmodel.navigation3)
}

data class RustAndroidTarget(
  val suffix: String,
  val triple: String,
  val abi: String,
  val clangPrefix: String,
)

val rustAndroidTargets =
  listOf(
    RustAndroidTarget("Arm64", "aarch64-linux-android", "arm64-v8a", "aarch64-linux-android"),
    RustAndroidTarget("X86_64", "x86_64-linux-android", "x86_64", "x86_64-linux-android"),
  )

val androidSdkDir =
  providers.environmentVariable("ANDROID_HOME").orElse("${System.getProperty("user.home")}/Library/Android/sdk")
val rustCrateDir = rootProject.file("rust/clipdock_p2p_jni")
val rustCargoProfile =
  providers.gradleProperty("clipdock.rustProfile")
    .orElse(providers.environmentVariable("CLIPDOCK_RUST_PROFILE"))
    .orElse("debug")
    .get()
val rustCargoProfileDir =
  when (rustCargoProfile) {
    "debug" -> "debug"
    "release" -> "release"
    else -> error("Unsupported Rust cargo profile for Android JNI: $rustCargoProfile")
  }
val ndkHostTag =
  System.getProperty("os.name").lowercase(Locale.US).let { osName ->
    when {
      osName.contains("mac") -> "darwin-x86_64"
      osName.contains("linux") -> "linux-x86_64"
      osName.contains("windows") -> "windows-x86_64"
      else -> error("Unsupported NDK host OS: $osName")
    }
  }
val ndkToolchainDir =
  androidSdkDir.map { "$it/ndk/27.3.13750724/toolchains/llvm/prebuilt/$ndkHostTag/bin" }

val copyRustJniTasks =
  rustAndroidTargets.map { target ->
    val cargoBuild =
      tasks.register<Exec>("cargoBuildP2p${target.suffix}") {
        workingDir = rustCrateDir
        inputs.file(rustCrateDir.resolve("Cargo.toml"))
        inputs.file(rustCrateDir.resolve("Cargo.lock"))
        inputs.dir(rustCrateDir.resolve("src"))
        outputs.file(rustCrateDir.resolve("target/${target.triple}/$rustCargoProfileDir/libclipdock_p2p_jni.so"))
        val upperTargetKey = target.triple.uppercase(Locale.US).replace("-", "_")
        val lowerTargetKey = target.triple.replace("-", "_")
        val clang = "${ndkToolchainDir.get()}/${target.clangPrefix}26-clang"
        val ar = "${ndkToolchainDir.get()}/llvm-ar"
        environment("CC_$upperTargetKey", clang)
        environment("AR_$upperTargetKey", ar)
        environment("CC_$lowerTargetKey", clang)
        environment("AR_$lowerTargetKey", ar)
        environment("CARGO_TARGET_${upperTargetKey}_LINKER", clang)
        val cargoBuildArgs = mutableListOf("build", "--target", target.triple)
        if (rustCargoProfile == "release") {
          cargoBuildArgs += "--release"
        }
        commandLine("cargo", *cargoBuildArgs.toTypedArray())
      }

    tasks.register<Copy>("copyP2pJni${target.suffix}") {
      dependsOn(cargoBuild)
      from(rustCrateDir.resolve("target/${target.triple}/$rustCargoProfileDir/libclipdock_p2p_jni.so"))
      into(layout.buildDirectory.dir("generated/rustJniLibs/${target.abi}"))
    }
  }

tasks.named("preBuild") {
  dependsOn(copyRustJniTasks)
}

val validateReleaseSigning =
  tasks.register<ValidateReleaseSigningTask>("validateReleaseSigning") {
    signingConfigured.set(releaseSigningConfigured)
    keystorePath.set(releaseKeystoreAbsolutePath ?: "")
  }

tasks.configureEach {
  if (name in setOf("assembleRelease", "bundleRelease", "packageRelease", "packageReleaseBundle", "signReleaseBundle")) {
    dependsOn(validateReleaseSigning)
  }
}
