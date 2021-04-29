#!/bin/bash
set -euC

exec 2>&1

readonly TMPDIR=tmp-$RANDOM/

## Prepare

printf 'Copying documentation from `%s` to temporary directory `%s`.\n' "$GENERATED_DOC_DIR" "$TMPDIR"
mkdir "$TMPDIR"
cp -R "$GENERATED_DOC_DIR"/* "$TMPDIR"

printf 'Setting up git user.\n'
git config user.name "GitHub"
git config user.email "noreply@github.com"

printf 'Fetching and going to documentation branch `%s`.\n' "$DOC_BRANCH"
git fetch origin "$DOC_BRANCH"
git checkout "$DOC_BRANCH"

##

printf 'Determining the kind of reference... '
case $GITHUB_REF in
    refs/heads/*) REF_KIND=branch ;;
    refs/tags/*)  REF_KIND=tag ;;
    *)
        printf 'I do not know what to do with ref `%s`.\n' "$REF"
        exit 7
esac
printf 'It is a %s.\n' "$REF_KIND"

REF=${GITHUB_REF##*/}
target=$TARGET_DOC_DIR/$REF_KIND/$REF

## Add the new documentation as a sub-directory of the documentation. If this is
## a branch, write the commit hash to a specific file.

printf 'Add the new documentation as a sub-directory `%s` of the full documentation.\n' "$target"
rm -rf "$target"
mkdir -p "$target"
mv "$TMPDIR"/* "$target"

if [ "$REF_KIND" = branch ]; then
    commit_hash_target=$target/commit-hash
    printf 'The reference is a branch, so we write the commit hash to `%s`.\n' "$commit_hash_target"
    echo "$GITHUB_SHA" > "$commit_hash_target"
fi

## Replace the index of the newly-added documentation by a redirection to the
## global index.

rm -f "$target"/index.html
cat <<EOF > "$target"/index.html
<!DOCTYPE html>
<html>
  <head>
    <meta http-equiv="refresh" content="0; url='../..'" />
  </head>
  <body>
    <p>Please follow <a href="../..">this link</a>.</p>
  </body>
</html>
EOF

## Regenerate the global index page to take into account the newly-added
## documentation.

printf '(Re)generate the global index page.\n'
rm -f "$TARGET_DOC_DIR"/index.html
{
    cat "$GITHUB_ACTION_PATH"/index-header.html
    printf '<h3>Tags</h3><ul>'

    ls -1 "$TARGET_DOC_DIR"/tag | sort -rn | \
        while read -r ref; do
            for lib in "$TARGET_DOC_DIR/tag/$ref"/*; do
                if [ -d "$lib" ]; then
                    lib=$(basename "$lib")
                    printf '<li><span class="version">%s</span> <a href="%s">%s</a></li>' "$ref" "tag/$ref/$lib/index.html" "$lib"
                fi
            done
        done

    printf '</ul><h3>Branches</h3><ul>'

    ls -1 "$TARGET_DOC_DIR"/branch | sort | \
        while read -r ref; do
            for lib in "$TARGET_DOC_DIR/branch/$ref"/*; do
                if [ -d "$lib" ]; then
                    lib=$(basename "$lib")
                    printf '<li><span class="version">%s@%s</span> <a href="%s">%s</a></li>' "$ref" "$(cat "$TARGET_DOC_DIR/branch/$ref/commit-hash" | head -c 7)" "branch/$ref/$lib/index.html" "$lib"
                fi
            done
        done

    cat "$GITHUB_ACTION_PATH"/index-footer.html
} > "$TARGET_DOC_DIR"/index.html

## Stage all the newly-added files, commit & push

printf 'Stage the targets.\n'
git add "$target"
git add "$TARGET_DOC_DIR"/index.html

printf 'Commit & push.\n'
git commit -m "$COMMIT_MESSAGE"
git push origin "$DOC_BRANCH"

printf 'Done!\n'
