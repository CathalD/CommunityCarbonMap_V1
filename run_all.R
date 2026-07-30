# =============================================================================
# run_all.R  --  run the pipeline.
#
# HOW TO USE THIS, from a fresh R session:
#
#   setwd("~/path/to/CommunityCarbonMap_V1")
#   source("run_all.R")          # defines run_steps(), runs nothing
#   run_steps()                  # everything, 01 -> 13
#
# One step at a time, which is what you want while iterating:
#
#   run_steps("01")              # just step 01
#   run_steps(c("01", "01b"))    # a couple
#   run_steps("06:13")           # a range, inclusive
#   run_steps(gee = FALSE)       # skip every step that needs Earth Engine
#
# Sourcing this file no longer runs the pipeline as a side effect. Sourcing a
# file and having it silently start a twenty-minute Earth Engine job is a nasty
# surprise, so run_steps() has to be called deliberately.
# =============================================================================

.args <- commandArgs(trailingOnly = FALSE)
.f <- sub("^--file=", "", grep("^--file=", .args, value = TRUE))
.o <- unlist(lapply(sys.frames(), function(e) e$ofile))
PROJ_DIR <- if (length(.f)) dirname(normalizePath(.f[[1]])) else
            if (length(.o)) dirname(normalizePath(.o[[1]])) else getwd()

# Steps 01-07 build the map. 08-13 are the external comparison and context
# add-on: they read the map pipeline's outputs, but nothing in 01-07 depends on
# them, so they can be skipped entirely.
STEPS <- c(
  "01"  = "01_clean_and_stocks.R",        # field data -> carbon stocks
  "01b" = "01b_plot_profiles.R",          # profile figures
  "02"  = "02_covariates.R",              # GEE: covariate stack + priors
  "03"  = "03_training_data.R",           # covariates at the cores
  "04"  = "04_train_model.R",             # random forest + leave-one-core-out CV
  "05"  = "05_predict_and_compare.R",     # predict + residuals vs the prior
  "06"  = "06_bayesian_update.R",         # fuse the prior with the cores
  "07"  = "07_version_and_export.R",      # hexagons, GeoPackage, version snapshot
  "08"  = "08_external_ingest.R",         # harmonise the four external databases
  "09"  = "09_external_ecosystem.R",      # GEE: wetland + land cover classes
  "10"  = "10_comparison_outputs.R",      # comparison figures + GeoPackage
  "11"  = "11_context_figures.R",         # the six context figures
  "12"  = "12_community_story.R",         # contribution figure + brief
  "13"  = "13_regional_comparison.R"      # GEE: four reference groups
)

# Steps needing an authenticated Earth Engine session.
GEE_STEPS <- c("02", "09", "13")

#' Run pipeline steps, in order.
#'
#' @param which step keys: "01", c("01","02"), or an inclusive range "06:13".
#'   Defaults to every step.
#' @param gee if FALSE, skips the Earth Engine steps and says which.
#' @param stop_on_error if FALSE, reports a failed step and continues to the
#'   next rather than aborting the whole run.
run_steps <- function(which = names(STEPS), gee = TRUE, stop_on_error = TRUE) {
  keys <- unlist(lapply(which, function(w) {
    if (grepl(":", w, fixed = TRUE)) {
      ends <- strsplit(w, ":", fixed = TRUE)[[1]]
      idx <- match(ends, names(STEPS))
      if (anyNA(idx)) stop("Unknown step in range '", w, "'", call. = FALSE)
      names(STEPS)[seq(idx[1], idx[2])]
    } else w
  }))
  unknown <- setdiff(keys, names(STEPS))
  if (length(unknown)) {
    stop("Unknown step(s): ", paste(unknown, collapse = ", "),
        "\n  Available: ", paste(names(STEPS), collapse = ", "), call. = FALSE)
  }
  if (!gee) {
    skipped <- intersect(keys, GEE_STEPS)
    if (length(skipped)) message("skipping Earth Engine steps: ",
                                paste(skipped, collapse = ", "))
    keys <- setdiff(keys, GEE_STEPS)
  }

  # Each step normally locates itself from its own file path. Sourced from here
  # that lookup would resolve to run_all.R instead, so hand the directory over
  # explicitly -- every step's bootstrap checks this variable first.
  Sys.setenv(CCM_R_DIR = file.path(PROJ_DIR, "R"))
  on.exit(Sys.unsetenv("CCM_R_DIR"), add = TRUE)

  for (k in keys) {
    cat("\n", strrep("=", 78), "\n", sep = "")
    cat("STEP ", k, "   ", STEPS[[k]],
        if (k %in% GEE_STEPS) "   [needs Earth Engine]" else "", "\n", sep = "")
    cat(strrep("=", 78), "\n")
    ok <- tryCatch({ source(file.path(PROJ_DIR, "R", STEPS[[k]])); TRUE },
                  error = function(e) { message("STEP ", k, " FAILED: ",
                                                conditionMessage(e)); FALSE })
    if (!ok && stop_on_error) {
      stop("Stopped at step ", k, ". Fix it, then resume with run_steps(\"",
          k, ":13\").", call. = FALSE)
    }
  }
  invisible(TRUE)
}

message("Project: ", PROJ_DIR)
message("Steps:   ", paste(names(STEPS), collapse = " "))
message("Run e.g.  run_steps()   run_steps(\"01\")   run_steps(\"06:13\")   run_steps(gee = FALSE)")
