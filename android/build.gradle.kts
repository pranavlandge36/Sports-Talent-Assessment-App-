import org.gradle.api.tasks.Delete
import org.gradle.api.file.Directory

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// === OPTIONAL: move build directory (use with caution) ===
// If you really need to relocate the build directory, set it explicitly.
// CAUTION: make sure the resolved path is correct and writable.
val newRootBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()

// Apply the new build dir only if you intentionally want to.
// If you don't need it, comment out the following block.
rootProject.layout.buildDirectory.set(newRootBuildDir)

subprojects {
    // Each subproject gets its own folder under the new root build dir
    val subprojectBuildDir = newRootBuildDir.dir(project.name)
    project.layout.buildDirectory.set(subprojectBuildDir)
}

// Avoid forcing evaluation unless necessary — remove if not required.
// project.evaluationDependsOn(":app")

// Register clean to delete the new build directory explicitly
tasks.register<Delete>("clean") {
    // delete expects File/Directory/Iterable<File>. Use asFile to be explicit.
    delete(newRootBuildDir.asFile)
}
