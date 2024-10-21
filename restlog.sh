#!/bin/sh
# copyright 2024 jdimpson at acm dot org

OCI="docker"
#JQ="$OCI run -i --rm ghcr.io/jqlang/jq:latest";
JQ="jq";
#CURL="$OCI run -it --rm curlimages/curl:latest"
CURL="curl";

docurl() {
	local URL="$1";
	local OUT="$2";
	local NUMRETRIES="$3";
	test $VERB -eq 1 && echo "connecting to $URL up to $NUMRETRIES times" >&2;
	for i in `seq $NUMRETRIES`; do
		$CURL -sS "$URL" >> "$OUT" 2> /dev/null;
		rc=$?;
		if test $rc -eq 0; then
			#exit 0;
			test $VERB -eq 1 && echo "succeeded" >&2;
			return 0;
		fi

		test $VERB -eq 1 && echo "attempt $i failed; sleeping $i seconds" >&2;
		sleep $i;
	done 
	echo "error communicating with $URL" >&2;
	# curl: (52) Empty reply from server
	# curl: (56) Recv failure: Connection reset by peer
	#exit 1;
	return 1;
}

maketemplate() {
	test -z "$DATAPT"       && local DATAPT="http://datapoint_url/rest/csv";
	test -z "$HED"          && local HED="http://header_url/rest/csvhed?delete_if_unneeded";
	test -z "$CURRENTSET"   && local CURRENTSET="working_data_file";
	test -z "$PREVIOUSSET"  && local PREVIOUSSET=null;
	test -z "$ARCHIVE"      && local ARCHIVE=true;
	test -z "$OUTPUTDIR"    && local OUTPUTDIR="./";
	test -z "$NUMRETRIES"   && local NUMRETRIES=10
	# make outputdir fully qualified
	if test -d "$OUTPUTDIR"; then
		OUTPUTDIR=$(cd "$OUTPUTDIR" && pwd);
	else
		echo "WARNING: output directory $OUTPUTDIR does not exist or is not accessible" >&2;
	fi

	# escape strings (unless null)
	# this section takes a long time when JQ is a docker container
	test "$DATAPT" = "null"      || DATAPT=$(echo "$DATAPT" | $JQ -R);
	test "$HED" = "null"         || HED=$(echo "$HED" | $JQ -R);
	test "$CURRENTSET" = "null"  || CURRENTSET=$(echo "$CURRENTSET"| $JQ -R);
	test "$PREVIOUSSET" = "null" || PREVIOUSSET=$(echo "$PREVIOUSSET" | $JQ -R);
	test "$OUTPUTDIR" = "null"   || OUTPUTDIR=$(echo "$OUTPUTDIR" | $JQ -R);
	# TODO: check that NUMRESTRIES is an integer

	test $VERB -eq 1 && echo "making template with DATAPT=$DATAPT HED=$HED CURRENTSET=$CURRENTSET PREVIOUSSET=$PREVIOUSSET ARCHIVE=$ARCHIVE OUTPUTDIR=$OUTPUTDIR NUMRETRIES=$NUMRETRIES" >&2;

	local template=$(cat<<EOF
{
  "datapt": $DATAPT,
  "hed":    $HED,
  "currentset": $CURRENTSET,
  "previousset": $PREVIOUSSET,
  "archive": $ARCHIVE,
  "outputdir": $OUTPUTDIR,
  "numretries": $NUMRETRIES
}
EOF
);
	$JQ --null-input "$template";
}

now_minute() {
	date "+%Y%m%d%H%M";
}

doarchive() {
	local CURRENTSET="$1";
	local PREVIOUSSET="$2";

	ext=$(echo "$CURRENTSET" | sed -e 's/^[^.]*//');

	if ! test -z "$ext"; then
		ARCH="$(now_minute)$ext";
	else
		ARCH=$(now_minute);
	fi
	# if previousset is set, rename current to it and copy previousset to dated archive file. 
	# else rename current to dated archive file.
	if ! test -z "$PREVIOUSSET"; then
		mv "$CURRENTSET" "$PREVIOUSSET";
		cp "$PREVIOUSSET" "$ARCH";
	else
		mv "$CURRENTSET" "$ARCH";
	fi
}

usage() {
	echo "Usage: $0 [-v] init    [--datapt http://foo.local/rest/csv] [--hed http://foo.local/rest/csvhed] [--currentset today.csv] [--outputdir ./foo-data ] > <json file>" >&2;
	echo "       $0 [-v] rotate  <json file>" >&2;
	echo "       $0 [-v] collect <json file>" >&2;
}

VERB=0;
if test "x$1" = "x--verbose" || test "x$1" = "x-v"; then
	VERB=1;
	shift;
fi

if test "$1" = "init"; then
	shift;
	while test $# -gt 0; do
		case "$1" in 
			"--datapt")
				DATAPT="$2";shift;shift;;
			"--hed")
				HED="$2";shift;shift;;
			"--currentset")
				CURRENTSET="$2";shift;shift;;
			"--previousset")
				PREVIOUSSET="$2";shift;shift;;
			"--archive")
				ARCHIVE="$2";shift;shift;;
			"--outputdir")
				OUTPUTDIR="$2";shift;shift;;
			"--numretries")
				NUMRETRIES="$2";shift;shift;;
			*)
				echo "Unknown argument $1, ignoring" >&2; shift;;
		esac;
	done;
	maketemplate;
	exit 0;
fi

if test "$1" = "collect" || test "$1" = "rotate"; then
	JSON="$2";
	if ! echo "$JSON" | egrep -q '^/'; then
		JSON="$(pwd)/$JSON";
	fi

	if ! test -r "$JSON"; then
		echo "ERROR: Can't read $JSON file, exiting" >&2;
		exit 2;
	fi
	# TODO: need error handling on these JSON lookups
	OUTPUTDIR=$($JQ -r .outputdir < "$JSON");
	NUMRETRIES=$($JQ -r .numretries < "$JSON");
	CURRENTSET=$($JQ -r .currentset < "$JSON");

	cd "$OUTPUTDIR" || { echo "ERROR: output directory $OUTPUTDIR does not exist or is not accessible." >&2; exit 3; }
	if test "$1" = "collect"; then
		DATAPT=$($JQ -r .datapt < "$JSON");
		if echo "$DATAPT" | egrep -q '^http'; then
			docurl "$DATAPT" "$CURRENTSET" $NUMRETRIES;
			RET=$?
		else
			if echo "$DATAPT" | grep -q ' '; then
				TESTCMD=`echo "$DATAPT" | sed -e 's/ .*//'`;
			else
				TESTCMD="$DATAPT";
			fi
			if test -x `which "$TESTCMD"`; then
				for i in `seq $NUMRETRIES`; do
					#$DATAPT >> "$CURRENTSET";
					O=$($DATAPT);
					RET=$?
					if test $RET -eq 0; then
						echo "$O" >> "$CURRENTSET";
						break;
					fi
					if ! test -z "$O"; then
						echo "Error running $DATAPT, throwing away output $O" >&2;
					fi
				done
			else
				echo "ERROR: datapt $TESTCMD is not a URL or executable." >&2;
				exit 4;
			fi
		fi
		rc=$RET;
	fi
	if test "$1" = "rotate"; then
		ARCHIVE=$($JQ -r .archive < "$JSON");
		PREVIOUSSET=$($JQ -r .previousset < "$JSON");
		if test "$PREVIOUSSET" = "null"; then
			PREVIOUSSET=
		fi
		if test -e "$CURRENTSET"; then
			if test $ARCHIVE = "true"; then
				doarchive "$CURRENTSET" "$PREVIOUSSET";
			else
				echo "previousset is $PREVIOUSSET";
				#if test "$PREVIOUSSET" = "null"; then
				if test -z "$PREVIOUSSET"; then
					cp /dev/null "$CURRENTSET";
				else
					mv "$CURRENTSET" "$PREVIOUSSET";
				fi
			fi
		fi
		HED=$($JQ -r .hed < "$JSON");
		if echo "$HED" | egrep -q '^http'; then
			docurl "$HED" "$CURRENTSET" $NUMRETRIES;
		else
			if test "$HED" = "null"; then
				# no header line needed
				true;
			else
				# assume the value for HED is the header to put into the file
				echo "$HED" > "$CURRENTSET"
			fi
		fi
		rc=$?;
	fi
	exit $rc;
fi

usage;
exit 0;
