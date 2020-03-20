#!/bin/bash

#       -x  Print commands and their arguments as they are executed.
set -x
#       -e  Exit immediately if a command exits with a non-zero status.
set -e

ROOTDIR=$(git rev-parse --show-toplevel)

# Render all the adocs that are not named Readme
find "$ROOTDIR" -name '*.adoc' | grep -i -v Readme | xargs -n1 -I {} asciidoctor -D "$ROOTDIR/docs" {}

# Render the OCS4 doc
asciidoctor -o "$ROOTDIR/docs/ocs.html" "$ROOTDIR/ocp4ocs4/ocs.adoc"
