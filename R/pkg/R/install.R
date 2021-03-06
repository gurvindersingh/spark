#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Functions to install Spark in case the user directly downloads SparkR
# from CRAN.

#' Download and Install Apache Spark to a Local Directory
#'
#' \code{install.spark} downloads and installs Spark to a local directory if
#' it is not found. The Spark version we use is the same as the SparkR version.
#' Users can specify a desired Hadoop version, the remote mirror site, and
#' the directory where the package is installed locally.
#'
#' The full url of remote file is inferred from \code{mirrorUrl} and \code{hadoopVersion}.
#' \code{mirrorUrl} specifies the remote path to a Spark folder. It is followed by a subfolder
#' named after the Spark version (that corresponds to SparkR), and then the tar filename.
#' The filename is composed of four parts, i.e. [Spark version]-bin-[Hadoop version].tgz.
#' For example, the full path for a Spark 2.0.0 package for Hadoop 2.7 from
#' \code{http://apache.osuosl.org} has path:
#' \code{http://apache.osuosl.org/spark/spark-2.0.0/spark-2.0.0-bin-hadoop2.7.tgz}.
#' For \code{hadoopVersion = "without"}, [Hadoop version] in the filename is then
#' \code{without-hadoop}.
#'
#' @param hadoopVersion Version of Hadoop to install. Default is \code{"2.7"}. It can take other
#'                      version number in the format of "x.y" where x and y are integer.
#'                      If \code{hadoopVersion = "without"}, "Hadoop free" build is installed.
#'                      See
#'                      \href{http://spark.apache.org/docs/latest/hadoop-provided.html}{
#'                      "Hadoop Free" Build} for more information.
#'                      Other patched version names can also be used, e.g. \code{"cdh4"}
#' @param mirrorUrl base URL of the repositories to use. The directory layout should follow
#'                  \href{http://www.apache.org/dyn/closer.lua/spark/}{Apache mirrors}.
#' @param localDir a local directory where Spark is installed. The directory contains
#'                 version-specific folders of Spark packages. Default is path to
#'                 the cache directory:
#'                 \itemize{
#'                   \item Mac OS X: \file{~/Library/Caches/spark}
#'                   \item Unix: \env{$XDG_CACHE_HOME} if defined, otherwise \file{~/.cache/spark}
#'                   \item Windows: \file{\%LOCALAPPDATA\%\\spark\\spark\\Cache}. See
#'                         \href{https://www.microsoft.com/security/portal/mmpc/shared/variables.aspx}{
#'                         Windows Common Folder Variables} about \%LOCALAPPDATA\%
#'                 }
#' @param overwrite If \code{TRUE}, download and overwrite the existing tar file in localDir
#'                  and force re-install Spark (in case the local directory or file is corrupted)
#' @return \code{install.spark} returns the local directory where Spark is found or installed
#' @rdname install.spark
#' @name install.spark
#' @aliases install.spark
#' @export
#' @examples
#'\dontrun{
#' install.spark()
#'}
#' @note install.spark since 2.1.0
#' @seealso See available Hadoop versions:
#'          \href{http://spark.apache.org/downloads.html}{Apache Spark}
install.spark <- function(hadoopVersion = "2.7", mirrorUrl = NULL,
                          localDir = NULL, overwrite = FALSE) {
  version <- paste0("spark-", packageVersion("SparkR"))
  hadoopVersion <- tolower(hadoopVersion)
  hadoopVersionName <- hadoop_version_name(hadoopVersion)
  packageName <- paste(version, "bin", hadoopVersionName, sep = "-")
  localDir <- ifelse(is.null(localDir), spark_cache_path(),
                     normalizePath(localDir, mustWork = FALSE))

  if (is.na(file.info(localDir)$isdir)) {
    dir.create(localDir, recursive = TRUE)
  }

  packageLocalDir <- file.path(localDir, packageName)

  if (overwrite) {
    message(paste0("Overwrite = TRUE: download and overwrite the tar file",
                   "and Spark package directory if they exist."))
  }

  # can use dir.exists(packageLocalDir) under R 3.2.0 or later
  if (!is.na(file.info(packageLocalDir)$isdir) && !overwrite) {
    fmt <- "Spark %s for Hadoop %s is found, and SPARK_HOME set to %s"
    msg <- sprintf(fmt, version, ifelse(hadoopVersion == "without", "Free build", hadoopVersion),
                   packageLocalDir)
    message(msg)
    Sys.setenv(SPARK_HOME = packageLocalDir)
    return(invisible(packageLocalDir))
  }

  packageLocalPath <- paste0(packageLocalDir, ".tgz")
  tarExists <- file.exists(packageLocalPath)

  if (tarExists && !overwrite) {
    message("tar file found.")
  } else {
    robust_download_tar(mirrorUrl, version, hadoopVersion, packageName, packageLocalPath)
  }

  message(sprintf("Installing to %s", localDir))
  untar(tarfile = packageLocalPath, exdir = localDir)
  if (!tarExists || overwrite) {
    unlink(packageLocalPath)
  }
  message("DONE.")
  Sys.setenv(SPARK_HOME = packageLocalDir)
  message(paste("SPARK_HOME set to", packageLocalDir))
  invisible(packageLocalDir)
}

robust_download_tar <- function(mirrorUrl, version, hadoopVersion, packageName, packageLocalPath) {
  # step 1: use user-provided url
  if (!is.null(mirrorUrl)) {
    msg <- sprintf("Use user-provided mirror site: %s.", mirrorUrl)
    message(msg)
    success <- direct_download_tar(mirrorUrl, version, hadoopVersion,
                                   packageName, packageLocalPath)
    if (success) return()
  } else {
    message("Mirror site not provided.")
  }

  # step 2: use url suggested from apache website
  message("Looking for site suggested from apache website...")
  mirrorUrl <- get_preferred_mirror(version, packageName)
  if (!is.null(mirrorUrl)) {
    success <- direct_download_tar(mirrorUrl, version, hadoopVersion,
                                   packageName, packageLocalPath)
    if (success) return()
  } else {
    message("Unable to find suggested mirror site.")
  }

  # step 3: use backup option
  message("To use backup site...")
  mirrorUrl <- default_mirror_url()
  success <- direct_download_tar(mirrorUrl, version, hadoopVersion,
                                 packageName, packageLocalPath)
  if (success) {
    return(packageLocalPath)
  } else {
    msg <- sprintf(paste("Unable to download Spark %s for Hadoop %s.",
                         "Please check network connection, Hadoop version,",
                         "or provide other mirror sites."),
                   version, ifelse(hadoopVersion == "without", "Free build", hadoopVersion))
    stop(msg)
  }
}

get_preferred_mirror <- function(version, packageName) {
  jsonUrl <- paste0("http://www.apache.org/dyn/closer.cgi?path=",
                        file.path("spark", version, packageName),
                        ".tgz&as_json=1")
  textLines <- readLines(jsonUrl, warn = FALSE)
  rowNum <- grep("\"preferred\"", textLines)
  linePreferred <- textLines[rowNum]
  matchInfo <- regexpr("\"[A-Za-z][A-Za-z0-9+-.]*://.+\"", linePreferred)
  if (matchInfo != -1) {
    startPos <- matchInfo + 1
    endPos <- matchInfo + attr(matchInfo, "match.length") - 2
    mirrorPreferred <- base::substr(linePreferred, startPos, endPos)
    mirrorPreferred <- paste0(mirrorPreferred, "spark")
    message(sprintf("Preferred mirror site found: %s", mirrorPreferred))
  } else {
    mirrorPreferred <- NULL
  }
  mirrorPreferred
}

direct_download_tar <- function(mirrorUrl, version, hadoopVersion, packageName, packageLocalPath) {
  packageRemotePath <- paste0(
    file.path(mirrorUrl, version, packageName), ".tgz")
  fmt <- paste("Downloading Spark %s for Hadoop %s from:\n- %s")
  msg <- sprintf(fmt, version, ifelse(hadoopVersion == "without", "Free build", hadoopVersion),
                 packageRemotePath)
  message(msg)

  isFail <- tryCatch(download.file(packageRemotePath, packageLocalPath),
                     error = function(e) {
                       message(sprintf("Fetch failed from %s", mirrorUrl))
                       print(e)
                       TRUE
                     })
  !isFail
}

default_mirror_url <- function() {
  "http://www-us.apache.org/dist/spark"
}

hadoop_version_name <- function(hadoopVersion) {
  if (hadoopVersion == "without") {
    "without-hadoop"
  } else if (grepl("^[0-9]+\\.[0-9]+$", hadoopVersion, perl = TRUE)) {
    paste0("hadoop", hadoopVersion)
  } else {
    hadoopVersion
  }
}

# The implementation refers to appdirs package: https://pypi.python.org/pypi/appdirs and
# adapt to Spark context
spark_cache_path <- function() {
  if (.Platform$OS.type == "windows") {
    winAppPath <- Sys.getenv("%LOCALAPPDATA%", unset = NA)
    if (is.na(winAppPath)) {
      msg <- paste("%LOCALAPPDATA% not found.",
                   "Please define the environment variable",
                   "or restart and enter an installation path in localDir.")
      stop(msg)
    } else {
      path <- file.path(winAppPath, "spark", "spark", "Cache")
    }
  } else if (.Platform$OS.type == "unix") {
    if (Sys.info()["sysname"] == "Darwin") {
      path <- file.path(Sys.getenv("HOME"), "Library/Caches", "spark")
    } else {
      path <- file.path(
        Sys.getenv("XDG_CACHE_HOME", file.path(Sys.getenv("HOME"), ".cache")), "spark")
    }
  } else {
    stop(sprintf("Unknown OS: %s", .Platform$OS.type))
  }
  normalizePath(path, mustWork = FALSE)
}
