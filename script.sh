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

commit_hash_target=$target/commit-hash
printf 'Write the commit hash to `%s`.\n' "$commit_hash_target"
echo "$GITHUB_SHA" > "$commit_hash_target"

date_target=$target/date
printf 'Write the date to `%s`.\n' "$date_target"
date +%s > "$date_target"

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
    print_table () {
        printf '<tr class="head"><td class="name">%s</td><td>Commit</td><td>Date</td><td>Libraries</td></tr>\n' "$1"

        ls -1 "$TARGET_DOC_DIR"/"$2" | {
            while read -r ref; do
                printf '%s\t%s\n' "$(cat "$TARGET_DOC_DIR"/"$2"/"$ref"/date)" "$ref"
            done
        } | sort -rn | cut -f 2 | {
            while read -r ref; do
                hash=$(cat "$TARGET_DOC_DIR"/"$2"/"$ref"/commit-hash)
                date=$(cat "$TARGET_DOC_DIR"/"$2"/"$ref"/date)
                libs=$(
                    for lib in "$TARGET_DOC_DIR"/"$2"/"$ref"/*; do
                        if [ -d "$lib" ]; then
                            basename "$lib"
                        fi
                    done
                    )
                nb_libs=$(echo "$libs" | wc -l)
                lib=$(echo "$libs" | head -n 1)
                libs=$(echo "$libs" | tail -n +2)

                if [ "$nb_libs" -eq 1 ]; then
                    rowspan=
                else
                    rowspan=$(printf ' rowspan="%s"' "$nb_libs")
                fi

                printf '<tr>'
                printf '<td%s class="name">%s</td>' "$rowspan" "$ref"
                printf '<td%s class="commit-hash">%s</td>' "$rowspan" "$(echo "$hash" | head -c 7)"
                printf '<td%s class="date">%s</td>' "$rowspan" "$(date -d @"$date" +'%b %d, %Y')"
                printf '<td class="link"><a href="%s">%s</a></td>' "$2"/"$ref"/"$lib" "$lib"
                printf '</tr>\n'

                printf '%s' "$libs" | while read -r lib; do
                    printf '<tr><td class="link"><a href="%s">%s</a></td></tr>\n' "$2"/"$ref"/"$lib" "$lib"
                done
            done
        }
    }

    cat "$GITHUB_ACTION_PATH"/index-header.html

    print_table 'Tags' tag
    print_table 'Branches' branch

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
