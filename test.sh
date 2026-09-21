#!/bin/sh

# Tests for bm and bm-sync: sh test.sh, or dash test.sh. The shell that runs
# this file also runs bm and bm-sync. Stand-ins for curl, dmenu, xclip and
# bm-sync play the server, the menu, the clipboard and the background sync.
# Thus the tests do not use the network or your files.

here=$(cd "$(dirname "$0")" && pwd)
# Where /proc exists, it gives the name of this shell.
sh=$(tr '\000' '\n' 2>/dev/null < /proc/$$/cmdline | sed -n 1p)
sh=${sh:-sh}
t=${TMPDIR:-/tmp}/sbm-test.$$
mkdir -m 700 "$t" || exit 1
trap 'rm -rf "$t"' EXIT
trap 'exit 1' HUP INT TERM
mkdir "$t/bin" "$t/srv"
srv=$t/srv
PATH=$t/bin:$PATH
export T="$t" BOOKMARKS="$t/bookmarks" USERTAGS="$t/usertags" SBM_SYNC_CONFIG="$t/sync"
pass=0
fail=0

# eq <name> <result> <expected>
eq () {
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
        printf 'ok   %s\n' "$1"
    else
        fail=$((fail + 1))
        printf 'FAIL %s: expected [%s], got [%s]\n' "$1" "$3" "$2"
    fi
}

# dmenu: each call takes the next line of $T/answers. It prints the first
# menu line that holds the answer. Else it prints the answer, as typed text.
cat > "$t/bin/dmenu" <<'EOF'
#!/bin/sh
a=$(sed -n 1p "$T/answers")
sed 1d "$T/answers" > "$T/answers.new"
mv "$T/answers.new" "$T/answers"
awk -v a="$a" 'index($0, a) && !n { print; n = 1 } END { if (!n) print a }'
EOF
# xclip: -o prints the clipboard, -i fills it.
cat > "$t/bin/xclip" <<'EOF'
#!/bin/sh
if [ "$1" = -o ]; then cat "$T/clip" 2>/dev/null; else cat > "$T/clip"; fi
EOF
# bm-sync: records its arguments. The tests of bm-sync use the real one.
cat > "$t/bin/bm-sync" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$T/bm-sync.log"
EOF
# curl: plays an sbm-sync server that keeps its file in $T/srv/file. Lines
# in $T/srv/other come from another device, once. With $T/srv/code, the
# server refuses with that status. With $T/srv/touch, bm adds a line during
# the request. With $T/srv/broken, bm-sync cannot read the answer. With
# $T/srv/hold, a process takes the write lock of bm during the request and
# keeps it; its pid goes to $T/srv/holder.
cat > "$t/bin/curl" <<'EOF'
#!/bin/sh
srv=$T/srv
printf '%s\n' "$*" >> "$srv/argv"
out= head= data= auth= url= password=
while [ $# -gt 0 ]; do
    case $1 in
        -o) out=$2; shift ;;
        -D) head=$2; shift ;;
        -w|--max-time|-X) shift ;;
        -H) case $2 in @*) auth=$(cat "${2#@}") ;; esac; shift ;;
        --data-binary) data=${2#@}; shift ;;
        --data-urlencode) case $2 in password@-) password=$(cat) ;; esac; shift ;;
        -*) ;;
        *) url=$1 ;;
    esac
    shift
done
answer () { printf '%s\n' "$2" > "$out"; printf '%s' "$1"; exit 0; }
case $url in
    */api/login)
        [ "$password" = 'secret pass ' ] || answer 401 'wrong email or password'
        answer 200 tok123 ;;
    */api/logout)
        echo logout >> "$srv/log"
        exit 0 ;;
esac
[ "$auth" = 'Authorization: Bearer tok123' ] || answer 401 'not signed in'
[ ! -e "$srv/code" ] || answer "$(cat "$srv/code")" 'sync is paused'
printf '%s\n' "${url#*base=}" >> "$srv/bases"
cat "$data" "$srv/other" > "$srv/file" 2>/dev/null
rm -f "$srv/other"
version=v$(cksum < "$srv/file" | cut -d ' ' -f 1)
echo "$version" >> "$srv/versions"
cp "$srv/file" "$out"
[ ! -e "$srv/broken" ] || { rm -f "$out"; mkdir "$out"; }
printf 'HTTP/1.1 200 OK\r\nsbm-version: %s\r\n\r\n' "$version" > "$head"
if [ -e "$srv/touch" ]; then
    rm -f "$srv/touch"
    echo 'https://c.example C | ' >> "$BOOKMARKS"
fi
if [ -e "$srv/hold" ]; then
    sleep 30 >/dev/null 2>&1 &
    echo $! > "$srv/holder"
    mkdir "$BOOKMARKS.lock" && echo $! > "$BOOKMARKS.lock/pid"
fi
printf 200
EOF
chmod +x "$t/bin/dmenu" "$t/bin/xclip" "$t/bin/bm-sync" "$t/bin/curl"
echo "shell: $sh"

# ---- bm ----

echo 'code  | code repos, docs' > "$USERTAGS"
printf 'https://old.example Old site | code\nhttps://new.example\tNew site\tcode\n' > "$BOOKMARKS"
echo old.example > "$t/answers"
$sh "$here/bm" -c
eq 'copy takes the URL of a line of bm' "$(cat "$t/clip")" https://old.example
echo new.example > "$t/answers"
$sh "$here/bm" -c
eq 'copy takes the URL of a line of the app' "$(cat "$t/clip")" https://new.example

: > "$BOOKMARKS"
printf '%s\n' https://add.example 'Add site' code done > "$t/answers"
$sh "$here/bm" -a
eq 'add writes the bookmark' "$(cut -d ' ' -f 1 "$BOOKMARKS")" https://add.example
# bm runs bm-sync in the background: wait for it.
i=0
while [ ! -s "$t/bm-sync.log" ] && [ $i -lt 10 ]; do
    sleep 1
    i=$((i + 1))
done
eq 'add runs bm-sync -q' "$(cat "$t/bm-sync.log" 2>/dev/null)" -q

# The write lock. The other process adds a line after two seconds, and then
# frees the lock.
: > "$BOOKMARKS"
mkdir "$BOOKMARKS.lock"
( sleep 2; echo 'https://first.example First | ' >> "$BOOKMARKS"
  rm -rf "$BOOKMARKS.lock" ) &
first=$!
echo "$first" > "$BOOKMARKS.lock/pid"
printf '%s\n' https://second.example Second done > "$t/answers"
SBM_LOCK_WAIT=10 $sh "$here/bm" -a
wait "$first"
eq 'add waits for the write lock, and adds after the other process' \
    "$(cut -d ' ' -f 1 "$BOOKMARKS" | tr '\n' ' ')" 'https://first.example https://second.example '

sleep 30 >/dev/null 2>&1 &
holder=$!
mkdir "$BOOKMARKS.lock" && echo "$holder" > "$BOOKMARKS.lock/pid"
printf '%s\n' https://new.example New done > "$t/answers"
SBM_LOCK_WAIT=1 $sh "$here/bm" -a 2>"$t/err"
eq 'add stops when the lock stays, says why, and adds nothing' \
    "$?:$(grep -c 'in use' "$t/err"):$(grep -c new.example "$BOOKMARKS")" '1:1:0'
kill "$holder"
rm -rf "$BOOKMARKS.lock"

true &
wait $!
mkdir "$BOOKMARKS.lock" && echo $! > "$BOOKMARKS.lock/pid"
printf '%s\n' https://after.example After done > "$t/answers"
SBM_LOCK_WAIT=1 $sh "$here/bm" -a
eq 'add takes over the lock of a process that is gone, and frees it' \
    "$(grep -c after.example "$BOOKMARKS"):$(ls -d "$BOOKMARKS.lock" 2>/dev/null)" '1:'

# ---- bm-sync ----

bs () {
    $sh "$here/bm-sync" "$@"
}

(unset BOOKMARKS; bs) 2>"$t/err"
eq 'without BOOKMARKS, bm-sync fails and says so' "$?:$(grep -c BOOKMARKS "$t/err")" 1:1

echo 'https://a.example A | code' > "$BOOKMARKS"
bs 2>"$t/err"
eq 'without an account, bm-sync fails and says how to sign in' \
    "$?:$(cat "$t/err")" '1:bm-sync: not signed in: run bm-sync login'

: > "$SBM_SYNC_CONFIG"
chmod 644 "$SBM_SYNC_CONFIG"
printf 'me@example.org\nsecret pass \n' | bs login https://sync.example/ >/dev/null 2>&1
eq 'login keeps the server and the token in a file that only you can read' \
    "$(ls -l "$SBM_SYNC_CONFIG" | cut -c 1-10) $(tr '\n' ' ' < "$SBM_SYNC_CONFIG")" \
    '-rw------- server=https://sync.example token=tok123 '
eq 'the password and the token are not in the arguments of curl' \
    "$(grep -c -e secret -e tok123 "$srv/argv")" 0
eq 'login syncs at once, without a version' \
    "$(cat "$srv/file")|$(cat "$srv/bases")" 'https://a.example A | code|'

printf 'https://b.example\tB\torg\n' > "$srv/other"
bs -q
eq 'sync writes the merged file' \
    "$(cat "$BOOKMARKS")" "$(printf 'https://a.example A | code\nhttps://b.example\tB\torg')"
eq 'sync keeps the version' "$(cat "$BOOKMARKS.sync")" "$(sed -n '$p' "$srv/versions")"
v=$(cat "$BOOKMARKS.sync")
bs -q
eq 'the next sync sends that version' "$(sed -n '$p' "$srv/bases")" "$v"

: > "$srv/touch"
bs -q
eq 'a bookmark that bm adds during a sync goes to the server too' \
    "$(grep -c c.example "$srv/file") $(grep -c c.example "$BOOKMARKS")" '1 1'

echo 402 > "$srv/code"
cp "$BOOKMARKS" "$t/file.before"
cp "$BOOKMARKS.sync" "$t/version.before"
bs -q 2>"$t/err"
eq 'on 402, bm-sync fails, says why, and keeps the file and the version' \
    "$?:$(cat "$t/err"):$(cmp -s "$t/file.before" "$BOOKMARKS" &&
        cmp -s "$t/version.before" "$BOOKMARKS.sync" && echo same)" \
    '1:bm-sync: sync is paused:same'
rm -f "$srv/code"

# While bm holds the write lock, bm-sync neither reads nor writes the file.
export SBM_LOCK_WAIT=1
echo 'https://other.example Other | ' > "$srv/other"
sleep 30 >/dev/null 2>&1 &
holder=$!
mkdir "$BOOKMARKS.lock" && echo "$holder" > "$BOOKMARKS.lock/pid"
bs -q 2>"$t/err"
rc=$?
kill "$holder"
rm -rf "$BOOKMARKS.lock"
eq 'bm-sync does not read the file while bm holds the lock, and says why' \
    "$rc:$(grep -c 'in use' "$t/err"):$(cmp -s "$t/file.before" "$BOOKMARKS" && echo same)" \
    '1:1:same'
: > "$srv/hold"
bs -q 2>"$t/err"
rc=$?
kill "$(cat "$srv/holder")"
rm -rf "$BOOKMARKS.lock" "$srv/hold"
eq 'bm-sync does not write while bm holds the lock, and keeps the version' \
    "$rc:$(cmp -s "$t/file.before" "$BOOKMARKS" &&
        cmp -s "$t/version.before" "$BOOKMARKS.sync" && echo same)" '1:same'
unset SBM_LOCK_WAIT

rm -f "$BOOKMARKS"
bs -q
eq 'bm-sync makes a missing file and sends it without a version' \
    "$([ -f "$BOOKMARKS" ] && echo made):$(sed -n '$p' "$srv/bases")" 'made:'

echo 'https://d.example D | ' >> "$BOOKMARKS"
: > "$srv/broken"
bs -q 2>/dev/null
eq 'after a failed write, bm-sync has no version, so the next sync deletes nothing' \
    "$?:$([ -e "$BOOKMARKS.sync" ] || echo none)" '1:none'
rm -f "$srv/broken"

mkdir "$BOOKMARKS.sync.lock"
echo $$ > "$BOOKMARKS.sync.lock/pid"
n=$(grep -c '' "$srv/bases")
bs -q
eq 'while a sync runs, bm-sync leaves a note for it and sends nothing' \
    "$?:$([ -e "$BOOKMARKS.sync.lock/again" ] && echo note):$(grep -c '' "$srv/bases")" \
    "0:note:$n"
true &
wait $!
echo $! > "$BOOKMARKS.sync.lock/pid"
bs -q
eq 'bm-sync takes a lock that a killed bm-sync left' \
    "$?:$(grep -c '' "$srv/bases")" "0:$((n + 1))"

eq 'status shows the server' "$(bs status | sed -n 1p)" 'server: https://sync.example'

bs -q logout
eq 'logout removes the config and signs out on the server' \
    "$([ -e "$SBM_SYNC_CONFIG" ] || echo gone) $(cat "$srv/log")" 'gone logout'
eq 'bm-sync leaves no lock' "$(ls -d "$BOOKMARKS.sync.lock" 2>/dev/null)" ''

# ---- make ----

if command -v make >/dev/null 2>&1; then
    (cd "$here" && make -s install DESTDIR="$t/dest" PREFIX=/usr) >/dev/null
    eq 'make install installs bm and bm-sync' \
        "$(cd "$t/dest/usr/bin" && for f in *; do [ -x "$f" ] && printf '%s ' "$f"; done)" \
        'bm bm-sync '
    (cd "$here" && make -s uninstall DESTDIR="$t/dest" PREFIX=/usr) >/dev/null
    eq 'make uninstall removes them' "$(ls "$t/dest/usr/bin")" ''
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
