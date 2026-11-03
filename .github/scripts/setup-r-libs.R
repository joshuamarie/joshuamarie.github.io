# Usage:
#   Rscript .github/scripts/setup-r-libs.R          (publish: strict restore)
#   Rscript .github/scripts/setup-r-libs.R update   (snapshot: self-healing)

args = commandArgs(trailingOnly = TRUE)
mode = if (length(args)) args[1] else "restore"

options(repos = c(CRAN = Sys.getenv("CRAN_REPO")))
lib = Sys.getenv("R_LIBS_USER")
dir.create(lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(lib, .libPaths()))

if (!requireNamespace("renv", quietly = TRUE)) {
    install.packages("renv", lib = lib)
}

restored = tryCatch(
    {
        renv::restore(library = lib, prompt = FALSE)
        TRUE
    },
    error = function(e) {
        message("renv::restore() failed: ", conditionMessage(e))
        FALSE
    }
)

if (!restored) {
    if (mode != "update") {
        stop("renv.lock cannot be restored. Run the 'Update renv lockfile' workflow.")
    }
    lock = renv::lockfile_read("renv.lock")
    from_repo = Filter(function(p) identical(p$Source, "Repository"), lock$Packages)
    renv::install(names(from_repo), library = lib, prompt = FALSE)
}

# Packages the site needs that may not be in the lockfile yet
# (knitr/rmarkdown/downlit/xml2 are needed by Quarto and by `code-link`)
needed = unique(
    c(
        "knitr",
        "rmarkdown",
        "downlit",
        "xml2",
        renv::dependencies(quiet = TRUE)$Package
    )
)
needed = intersect(needed, rownames(available.packages()))
missing = setdiff(needed, rownames(installed.packages()))
if (length(missing)) {
    renv::install(missing, library = lib, prompt = FALSE)
}

if (mode == "update") {
    renv::update(library = lib, prompt = FALSE)
    renv::snapshot(
        library = .libPaths(),
        lockfile = "renv.lock",
        type = "implicit",
        prompt = FALSE
    )

    # Never commit a lockfile whose packages cannot be loaded
    snapshot = renv::lockfile_read("renv.lock")
    broken = Filter(
        function(pkg) !requireNamespace(pkg, quietly = TRUE),
        names(snapshot$Packages)
    )
    if (length(broken)) {
        stop("Packages in renv.lock fail to load: ", paste(broken, collapse = ", "))
    }
}
