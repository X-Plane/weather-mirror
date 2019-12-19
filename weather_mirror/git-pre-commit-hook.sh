#!/bin/sh

#
# Linter Elixir files using Credo.
# Called by "git receive-pack" with arguments: refname sha1-old sha1-new
#
# Config (in .git/config, [credo] section)
# ------
# credo.terminate
#   The credo exit status level to be considered as "not passed"---to prevent
#   git commit until fixed.

# Config
terminate_on=$(git config --int credo.terminate)
if [[ -z "$terminate_on" ]]; then terminate_on=16; fi

# lint it :: credo checks before commit
mix credo --strict
CREDO_RES=$?
if [ $CREDO_RES -ge $terminate_on ]; then
  echo ""
  echo "☆ ==================================== ☆"
	echo "☆ Credo found problems with your code. ☆" >&2
	echo "☆ Please fix the issues above before   ☆" >&2
	echo "☆ committing.                          ☆" >&2
  echo "☆ ==================================== ☆"
  echo ""
  exit $CREDO_RES
else
  echo ""
  echo "★ ============================== ★"
  echo "★   Credo linter passed.         ★"
  echo "★ ============================== ★"
  echo ""
fi

mix format --check-formatted
FORMAT_RES=$?
if [ $FORMAT_RES -ne 0 ]
then
  echo ""
  echo "☆ ==================================== ☆"
	echo "☆  Format check failed.                ☆" >&2
	echo "☆  Please run $ mix format             ☆" >&2
	echo "☆  before committing.                  ☆" >&2
  echo "☆ ==================================== ☆"
  echo ""
  exit $FORMAT_RES
fi

# test it :: run tests before commit (silently)
mix test 2>&1 >/dev/null
TEST_RES=$?
if [ $TEST_RES -ne 0 ]
then
  echo ""
  echo "☆ ==================================== ☆"
	echo "☆  One or more tests failed.           ☆" >&2
	echo "☆  Please fix them before committing.  ☆" >&2
  echo "☆ ==================================== ☆"
  echo ""
  exit $TEST_RES
else
  echo ""
  echo "★ ============================== ★"
  echo "★   Tests passed.                ★"
  echo "★ ============================== ★"
  echo ""
fi

exit 0
