#' Combine data frames with columns of class `labelled`
#'
#' @param ... data frames to bind together, potentially with columns of
#'   class "labelled". The first argument can be a list of data frames, similar
#'   to `plyr::rbind.fill`.
#' @param labels A named list providing vectors of value labels or describing
#'   how to handle columns of class `labelled`. See details for usage.
#' @param warn Logical indicating to warn if combining variables with different
#'   value labels. Defaults to TRUE.
#'
#' @return A data frame.
#'
#' @details
#' The argument `labels` provides options for how to handle binding of
#' columns of class `labelled`. Typical use is to provide a named list
#' with elements for each labelled column. Elements of the list
#' are either a vector of labels that should be applied to the column
#' or the character string "concatenated", which indicates that labels
#' should be concatenated such that all unique labels are distinct
#' values in the combined vector. This is accomplished by converting
#' to character strings, binding, and then casting back to labelled.
#' For labelled columns for which labels are not provided in the `label`
#' argument, the default behaviour is that the labels from the first
#' data frame with labels for that column are inherited by the combined
#' data.
#'
#' See examples.
#'
#' @examples
#' df1 <- data.frame(
#' area = haven::labelled(c(1L, 2L, 3L), c("reg 1"=1,"reg 2"=2,"reg 3"=3)),
#' climate = haven::labelled(c(0L, 1L, 1L), c("cold"=0,"hot"=1))
#' )
#' df2 <- data.frame(
#' area    = haven::labelled(c(1L, 2L), c("reg A"=1, "reg B"=2)),
#' climate = haven::labelled(c(1L, 0L), c("cold"=0, "warm"=1))
#' )
#'
#' # Default: all data frames inherit labels from first df. Incorrect if
#' # "reg 1" and "reg A" are from different countries, for example.
#' dfA <- rbind_labelled(df1, df2)
#' haven::as_factor(dfA)
#'
#' # Concatenate value labels for "area". Regions are coded separately,
#' # and original integer values are lost (by necessity of more levels now).
#' # For "climate", codes "1 = hot" and "1 = warm", are coded as the same
#' # outcome, inheriting "1 = hot" from df1 by default.
#' dfB <- rbind_labelled(df1, df2, labels=list(area = "concatenate"))
#' dfB
#' haven::as_factor(dfB)
#'
#' # We can specify to code as "1=warm/hot" rather than inheriting "hot".
#' dfC <- rbind_labelled(df1, df2,
#' labels=list(area = "concatenate", climate = c("cold"=0, "warm/hot"=1)))
#'
#' dfC$climate
#' haven::as_factor(dfC)
#'
#' # Or use `climate="concatenate"` to code "warm" and "hot" as different.
#' dfD <- rbind_labelled(df1, df2,
#' labels=list(area = "concatenate", climate="concatenate"))
#'
#' dfD
#' haven::as_factor(dfD)
#'
#' @export
rbind_labelled <- function(..., labels=NULL, warn=TRUE) {
  dfs <- list(...)
  if (is.list(dfs[[1]]) && !is.data.frame(dfs[[1]])) {
    dfs <- dfs[[1]]
  }

  # what kind of dataset is it we are working with
  if (is.element("label.table", attributes(dfs[[1]]) %>% names())) {
    type <- "foreign"
  } else if (any(lapply(dfs[[1]], class) %>% unlist() == "labelled")) {
    type <- "labelled"
  } else if (any(lapply(dfs[[1]], attributes) %>%
                 lapply(names) %>% unlist() == "label")) {
    type <- "reformat"
  } else {
    type <- "reformat"
  }

  # if the data has names let's grab that and append it
  if (!is.null(names(dfs))) {
    df_names <- names(dfs)
    for (i in seq_len(length(dfs))) {
      dfs[[i]]$DATASET <- df_names[i]
    }
  }

  # if its a foregin or reformatted dataset list then skip over the labelling
  if (!is.element(type, c("foreign", "reformat"))) {

    ## Ensure same column ordering for all dfs
    dfs <- lapply(dfs, "[", names(dfs[[1]]))

    # check to see if variables are labelled
    islab <- vapply(dfs, function(x){
        vapply(x, haven::is.labelled, logical(1))
      }, logical(length(dfs[[1]])))

    ## let's catch for one variable dataframes
    islab_vec_catch <- function(islab_obj) {
      if (is.vector(islab_obj)) {
        islab_obj <- t(islab_obj)
        colnames(islab_obj) <- names(dfs)
        rownames(islab_obj) <- names(dfs[[1]])[1]
      }
      islab_obj
    }

    islab <- islab_vec_catch(islab)
    anylab <- names(which(apply(islab, 1, any)))

    ## Convert "concatenated" variables to characters (will be converted later).
    catvar <- intersect(anylab, names(which(labels == "concatenate")))
    dfs <- lapply(dfs, function(x) {
      x[catvar] <- lapply(catvar, function(v) {
        as.character(haven::as_factor(x[[v]]))
      })
      x
    })
    labels <- labels[!names(labels) %in% catvar]

    islab <- vapply(
      dfs, function(x){
        vapply(x, haven::is.labelled, logical(1))
      },
      logical(length(dfs[[1]]))
    ) %>% islab_vec_catch()

    anylab <- names(which(apply(islab, 1, any)))
    needslab <- setdiff(anylab, names(labels))

    if (warn) {
      partlab <- intersect(names(which(apply(islab, 1, any) &
                                         !apply(islab, 1, all))),
                           needslab)
      if (length(partlab)) {
        warning(paste("Some variables are only partially labelled:",
                      paste(partlab, collapse = ", ")))
      }

      lablist <- lapply(dfs, "[", intersect(anylab, needslab))
      lablist <- lapply(lablist, lapply, attr, "labels")
      lablist <- do.call(Map, c(f = list, lablist))

      allequal <- lapply(lablist, function(x) {
        lapply(x, function(y) {
          identical(y, x[[1]])
        }) %>% unlist %>% all
      }) %>% unlist

      if (!is.null(allequal)) {
        if (any(!allequal)) {
          warning(paste0(
            "Some variables have non-matching value labels: ",
            paste(names(allequal[!allequal]), collapse = ", "),
            ".\nInheriting labels from first data frame with labels."
          ))
        }
      }
    }

    ## Grab inherited labels
    if (dim(islab[needslab, , drop = FALSE])[1] > 0) {
      whichlab <- apply(islab[needslab, , drop = FALSE], 1,
                        function(x) min(which(x)))
      if (length(whichlab)) {
        inherlab <- setNames(
          lapply(Map("[[", dfs[whichlab], names(whichlab)), attr, "labels"),
          names(whichlab)
        )
        labels <- c(labels, inherlab)
      }
    }

    ## rbind data frames
    df <- do.call(rbind, dfs)

    ## Add labels
    df[names(labels)] <- Map(haven::labelled, df[names(labels)], labels)

    ## Convert concatenated variables back to labelled
    df[catvar] <- lapply(df[catvar], factor)
    df[catvar] <- lapply(df[catvar], function(x)
      haven::labelled(as.integer(x), setNames(seq_along(levels(x)), levels(x))))

  } else {

    ## rbind data frames
    df <- do.call(rbind, dfs)

  }

  return(df)
}
