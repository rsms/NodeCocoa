#!/bin/bash
cd "${TARGET_BUILD_DIR}/${PUBLIC_HEADERS_FOLDER_PATH}"
patterns=( )
i=0
for file in *.h; do
  patterns[$i]='s#include <'"$file"'>#include <NodeJS\/'"$file"'>#g'
  let "i = $i + 1"
done
if [ "$?" != "0" ]; then exit $?; fi

for file in *.h; do
  buf=$(cat "$file")
  i=0
  count=${#patterns[@]}
  while [ "$i" -lt "$count" ]; do
    buf=$(echo "$buf" | sed -E "${patterns[$i]}")
    if [ "$?" != "0" ]; then exit $?; fi
    let "i = $i + 1"
  done
  echo "$buf" > "$file"
  echo $file
done


