import groovy.json.JsonSlurper
import org.gradle.api.file.DuplicatesStrategy
import org.gradle.api.plugins.JavaPluginExtension
import org.gradle.api.tasks.Exec
import org.gradle.api.tasks.SourceSetContainer
import org.gradle.api.tasks.compile.JavaCompile
import org.gradle.jvm.tasks.Jar
import java.util.zip.ZipFile

plugins {
  base
}

val minecraftManifest = layout.projectDirectory.file("ground_truth/26.1.2.json").asFile
val groundTruthJar = layout.projectDirectory.file("ground_truth/26.1.2.jar").asFile

fun minecraftLibraries(): List<String> {
  if (!minecraftManifest.isFile) {
    return emptyList()
  }

  @Suppress("UNCHECKED_CAST")
  val manifest = JsonSlurper().parse(minecraftManifest) as Map<String, Any?>

  @Suppress("UNCHECKED_CAST")
  val libraries = manifest["libraries"] as? List<Map<String, Any?>> ?: return emptyList()

  return libraries
    .mapNotNull { library -> library["name"] as? String }
    .filter { notation ->
      val coordinateParts = notation.count { character -> character == ':' }
      coordinateParts == 2 || coordinateParts == 3
    }
    .distinct()
}

val manifestLibraries = minecraftLibraries()
val compileOnlyLibraries = manifestLibraries + "org.jetbrains:annotations:26.1.0"
val javacDiagnosticCap = "1000000"
val javacWorkerHeapSize = providers.gradleProperty("javacWorker.heapSize").orElse("4g")

subprojects {
  apply(plugin = "java-library")

  extensions.configure<JavaPluginExtension> {
    toolchain {
      languageVersion.set(
        JavaLanguageVersion.of(
          providers.gradleProperty("javaCompiler.languageVersion").orElse("25").get().toInt(),
        ),
      )
    }
  }

  tasks.withType<JavaCompile>().configureEach {
    options.encoding = "UTF-8"
    options.isFork = true
    options.forkOptions.memoryMaximumSize = javacWorkerHeapSize.get()
    options.compilerArgs.addAll(
      listOf(
        "-Xlint:all",
        "-Werror",
        "-parameters",
        "-Xmaxerrs",
        javacDiagnosticCap,
        "-Xmaxwarns",
        javacDiagnosticCap,
      ),
    )
  }

  dependencies {
    compileOnlyLibraries.forEach { notation ->
      add("compileOnly", notation)
    }
    manifestLibraries.forEach { notation ->
      add("runtimeOnly", notation)
    }
  }

  tasks.register("printCompileClasspath") {
    doLast {
      configurations
        .getByName("compileClasspath")
        .resolve()
        .sortedBy { file -> file.absolutePath }
        .forEach { file -> println(file.absolutePath) }
    }
  }
}

fun Project.registerRunnableJar(taskName: String, fileName: String, mainClassName: String) {
  val runtimeClasspath = configurations.named("runtimeClasspath")
  val sourceSets = extensions.getByType<SourceSetContainer>()

  tasks.register<Jar>(taskName) {
    group = "distribution"
    description = "Builds a java -jar runnable Minecraft artifact with runtime dependencies bundled."
    archiveFileName.set(fileName)
    destinationDirectory.set(rootProject.layout.buildDirectory.dir("runnable"))
    duplicatesStrategy = DuplicatesStrategy.EXCLUDE

    manifest {
      attributes(
        "Main-Class" to mainClassName,
        "Multi-Release" to "true",
      )
    }

    from(sourceSets.getByName("main").output)
    from(rootProject.zipTree(groundTruthJar)) {
      include("assets/**")
      include("data/**")
      include("pack.png")
      include("flightrecorder-config.jfc")
      include("version.json")
      include("META-INF/LICENSE")
      exclude("**/*.class")
      exclude("**/*.java")
      exclude("**/*.kt")
      exclude("**/*.groovy")
      exclude("**/*.scala")
      exclude("META-INF/MANIFEST.MF")
      exclude("META-INF/*.SF")
      exclude("META-INF/*.RSA")
      exclude("META-INF/*.DSA")
    }
    from({
      runtimeClasspath.get().filter { file -> file.exists() }.map { file ->
        if (file.isDirectory) file else rootProject.zipTree(file)
      }
    }) {
      exclude("META-INF/MANIFEST.MF")
      exclude("META-INF/*.SF")
      exclude("META-INF/*.RSA")
      exclude("META-INF/*.DSA")
    }
    dependsOn(runtimeClasspath)
  }
}

val runnableJarTasks = listOf(":minecraft-server:runnableServerJar", ":minecraft-client:runnableClientJar")

val verifyNoGroundTruthCodeInRunnableJars = tasks.register("verifyNoGroundTruthCodeInRunnableJars") {
  group = "verification"
  description = "Fails if runnable jars contain ground-truth bytecode/source instead of reconstructed classes."
  dependsOn(runnableJarTasks)

  doLast {
    val groundTruthClasses = ZipFile(groundTruthJar).use { archive ->
      archive.entries().asSequence()
        .filter { entry -> !entry.isDirectory && entry.name.endsWith(".class") }
        .map { entry -> entry.name }
        .toSet()
    }

    val reconstructedClasses = subprojects.flatMap { subproject ->
      val classesDir = subproject.layout.buildDirectory.dir("classes/java/main").get().asFile
      if (!classesDir.isDirectory) {
        emptyList()
      } else {
        classesDir.walkTopDown()
          .filter { file -> file.isFile && file.extension == "class" }
          .map { file -> file.relativeTo(classesDir).invariantSeparatorsPath }
          .toList()
      }
    }.toSet()

    val sourceSuffixes = listOf(".java", ".kt", ".groovy", ".scala")
    val runnableJars = listOf(
      layout.buildDirectory.file("runnable/demcstify-server.jar").get().asFile,
      layout.buildDirectory.file("runnable/demcstify-client.jar").get().asFile,
    )

    val failures = mutableListOf<String>()
    runnableJars.forEach { runnableJar ->
      ZipFile(runnableJar).use { archive ->
        val entries = archive.entries().asSequence()
          .filter { entry -> !entry.isDirectory }
          .map { entry -> entry.name }
          .toList()
        val embeddedSourceEntries = entries.filter { entry -> sourceSuffixes.any(entry::endsWith) }
        val groundTruthOnlyClasses = entries
          .filter { entry -> entry.endsWith(".class") && entry in groundTruthClasses && entry !in reconstructedClasses }

        if (embeddedSourceEntries.isNotEmpty()) {
          failures += "${runnableJar.name} contains source entries: ${embeddedSourceEntries.take(20)}"
        }
        if (groundTruthOnlyClasses.isNotEmpty()) {
          failures += "${runnableJar.name} contains ground-truth-only class entries: ${groundTruthOnlyClasses.take(20)}"
        }
      }
    }

    if (failures.isNotEmpty()) {
      throw GradleException(failures.joinToString(System.lineSeparator()))
    }
  }
}

tasks.named("check") {
  dependsOn(verifyNoGroundTruthCodeInRunnableJars)
}

project(":minecraft-common") {
  tasks.withType<JavaCompile>().configureEach {
    options.compilerArgs.add("-implicit:none")
    options.sourcepath = files(project(":minecraft-server").layout.projectDirectory.dir("src/main/java"))
  }
}

project(":blaze3d") {
  dependencies {
    add("compileOnly", project(":minecraft-common"))
    add("compileOnly", project(":minecraft-server"))
  }

  tasks.withType<JavaCompile>().configureEach {
    options.compilerArgs.add("-implicit:none")
    options.sourcepath = files(
      layout.projectDirectory.dir("src/main/java"),
      project(":minecraft-client").layout.projectDirectory.dir("src/main/java"),
      project(":minecraft-server").layout.projectDirectory.dir("src/main/java"),
    )
  }
}

project(":minecraft-server") {
  dependencies {
    add("implementation", project(":minecraft-common"))
  }

  registerRunnableJar("runnableServerJar", "demcstify-server.jar", "net.minecraft.server.Main")
}

project(":minecraft-client") {
  dependencies {
    add("implementation", project(":blaze3d"))
    add("implementation", project(":minecraft-common"))
    add("implementation", project(":minecraft-server"))
  }

  registerRunnableJar("runnableClientJar", "demcstify-client.jar", "net.minecraft.client.main.Main")
}

tasks.register("runnableJars") {
  group = "distribution"
  description = "Builds both dependency-bundled java -jar artifacts."
  dependsOn(verifyNoGroundTruthCodeInRunnableJars)
}

val allSubprojectClasses = subprojects.map { subproject -> "${subproject.path}:classes" }

val bytecodeDiff = tasks.register<Exec>("bytecodeDiff") {
  group = "verification"
  description = "Compares one reconstructed class against the original JAR at Tier A. Use -PclassFqn=..."
  dependsOn(allSubprojectClasses)

  val classFqn = providers.gradleProperty("classFqn")
  doFirst {
    if (!classFqn.isPresent) {
      throw GradleException("bytecodeDiff requires -PclassFqn=<fully.qualified.ClassName>")
    }

    val command = mutableListOf(
      "node",
      layout.projectDirectory.file("scripts/bytecode-diff.mjs").asFile.absolutePath,
      "--class",
      classFqn.get(),
    )

    providers.gradleProperty("attemptId").orNull?.let { attemptId ->
      command.addAll(listOf("--attempt-id", attemptId))
    }
    providers.gradleProperty("progressDb").orNull?.let { progressDb ->
      command.addAll(listOf("--db", progressDb))
    }

    commandLine(command)
  }
}

tasks.register("bytecode-diff") {
  group = "verification"
  description = "Alias for bytecodeDiff."
  dependsOn(bytecodeDiff)
}
