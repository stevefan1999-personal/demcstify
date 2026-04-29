pluginManagement {
  repositories {
    gradlePluginPortal()
    mavenCentral()
  }
}

plugins {
  id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

dependencyResolutionManagement {
  repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
  repositories {
    maven("https://libraries.minecraft.net")
    mavenCentral()
  }
}

rootProject.name = "demcstify"

include(
  ":authlib",
  ":blaze3d",
  ":brigadier",
  ":datafixerupper",
  ":minecraft-client",
  ":minecraft-common",
  ":minecraft-server",
)

project(":authlib").projectDir = file("subprojects/authlib")
project(":blaze3d").projectDir = file("subprojects/blaze3d")
project(":brigadier").projectDir = file("subprojects/brigadier")
project(":datafixerupper").projectDir = file("subprojects/datafixerupper")
project(":minecraft-client").projectDir = file("subprojects/minecraft-client")
project(":minecraft-common").projectDir = file("subprojects/minecraft-common")
project(":minecraft-server").projectDir = file("subprojects/minecraft-server")
