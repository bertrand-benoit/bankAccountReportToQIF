#!/bin/bash
#
# Author: Bertrand BENOIT <bertrand.benoit@bsquare.no-ip.org>
# Version: 1.0
# Description: converts bank report (in pdf) to QIF format.
#
# usage: see usage function

#####################################################
#                Configuration
#####################################################

tmpDir="/tmp"
textFile="$tmpDir/"$( date +"%s" )"-"$( basename $0 )"-tmp"
tmpFile1="$textFile.tmp1"
tmpFile2="$textFile.tmp2"
DEFAULT_YEAR=$( date "+%Y" )
DEBUG=2

# Transactions exclusion pattern (some recurrent transaction which are embedded to GNU/Cash).
EXCLUDE_PATTERN="PENSION|LOYER|CIRCLE"

# Bank report exclusion pattern (some useless bank report information).
REPORT_EXCLUDE_PATTERN="SOLDE CREDITEUR|SOLDE AU |Rappel|opérations courante|www.bnpparibas.net|Minitel|code secret|Votre conseiller|tarification|prélévé au début|mois suivant|ce tarif|s'appliquent|conseiller|bénéficiez"

#####################################################
#                Defines usages.
#####################################################
function usage {
  echo -e "usage: $0 -i|--input <pdf file> [-o|--output <QIF file>] [-y|--year <year>] [-h|--help]"
  echo -e "-h|--help\tshow this help"
  echo -e "<input>\tbank report in PDF format"
  echo -e "<output>\tQIF format output file"
  echo -e "<year>\t\tyear to add to transaction (default: $DEFAULT_YEAR)"
  exit 1
}

#####################################################
#                Command line management.
#####################################################

year=$DEFAULT_YEAR
while [ "$1" != "" ]; do
  if [ "$1" == "-i" ] || [ "$1" = "--input" ]; then
    shift
    input="$1"
  elif [ "$1" == "-o" ] || [ "$1" = "--output" ]; then
    shift
    output="$1"
  elif [ "$1" == "-y" ] || [ "$1" = "--year" ]; then
    shift
    year="$1"
  elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
  else
    echo "Unknown parameter '$1'"
    usage
  fi

  shift
done

[ -z "$input" ] && echo -e "You must specify input file" >&2 && usage
[ ! -f "$input" ] && echo -e "Specified input file '$input' must exist" >&2 && usage

[ -z "$output" ] && [ -f "$output" ] && echo -e "Specified output file '$output' must NOT exist" >&2 && usage

#####################################################
#                Functions
#####################################################

# usage: convertInputFile <input as PDF> <output as text>
function convertInputFile() {
  [ $DEBUG -ge 2 ] && echo "DEBUG: converting $1 to $2"
  pdftotext -layout "$1" "$2" 2>/dev/null

  # Replaces any slash to avoid issue.
  sed -i 's@/@ @g;' "$2"

  # In some unknown situations, there is more than one space characters (2 or 3) at the beginning of important lines ...
  #  ensures there is only one.
  #sed -i 's/^[ ][ ]\([0-9]\)/ \1/;s/^[ ][ ][ ]\([0-9]\)/ \1/;' "$2"
}

# usage: extractInformation <input as text> <output as text>
# Adds '+' or '-' character to introduce value.
function manageValue() {
  local _inputFile="$1"
  local _tmpFile="$2"

  [ -f "$_tmpFile" ] && rm -f "$_tmpFile"

  # Information: until banq report of 09/2012, there was always between 5 and 14 space characters; since then, there can be 16 ...
  plusSignCount=0
  for informationRaw in $( cat "$_inputFile" |grep -E "^[ ]{1,3}[0-9]|^[ ]{5,16}[A-Z0-9*]" |grep -vE "$REPORT_EXCLUDE_PATTERN" \
                            |sed -e 's/USA \([0-9][0-9,]*\)USD+COMMISSION : \([0-9][0-9,]*\)/USA_COMMISSION/g;' \
                            |sed -e 's/[ ]\([.,]\)[ ]/\1/g;s/[ ]/£/g;' ); do
    information=$( echo "$informationRaw" |sed -e "s/\([0-9][0-9]*\)[.]\([0-9][0-9]*[,][0-9][0-9]\)$/\1\2/g;" |sed -e 's/£/ /g' )

    # echo "information: $information ($_tmpFile)"

    # Defines the value sign (it is '+' if and only if there is more than 175 characters).
    [ $( echo "$information" |wc -m ) -gt 175 ] && sign="+" || sign="-"
    [ "$sign" = "+" ] && let plusSignCount++

    # Updates the potential value on the line.
    information=$( echo "$information" |sed -e "s/\([0-9][0-9]*[,][0-9][0-9]\)$/$sign\1/g" )

    # Writes to the output file.
    echo "$information" >> "$_tmpFile"
  done

  [ $plusSignCount -gt 5 ] && echo -e "\E[31m\E[4mWARNING: it seems there is too much incoming after convert ($plusSignCount)\E[0m" >&2
}

# usage: formatLabel <label>
function formatLabel() {
  local _label="$1"

  # The aim is to remove useless information for GNU/Cash to match corresponding
  #  accounts from previous import.

  # Removes useless "date info." and "SEPA info" from label.
  _label=$( echo "$_label" |sed -E 's/DU [0-9]{6}[ ]//g;s/FACTURE.S.[ ]CARTE[ ]4974XXXXXXXX4230[ ]//g;s/NUM[ ][0-9]{6}[ ]ECH.*$//g;' )
  _label=$( echo "$_label" |sed -E 's/ECH[ ][0-9]{6}[ ]ID EMETTEUR.*$//g;' )
  _label=$( echo "$_label" |sed -E 's/RETRAIT DAB [0-9\/]{8}[ ][0-9Hh]{5}/RETRAIT DAB /g;s/[ ]BENOIT BERTRAND.*$//g;s/C.P.A.M..*$/C.P.A.M./' )
  _label=$( echo "$_label" |sed -E 's/[0-9]{0,}FRAIS SANTE[ ][0-9].*$/SANTE/;s/VTL[ ][0-9]{2}\/[0-9]{2}[ ][0-9]{2}[hH][0-9]{2}[ ]V[0-9]{1,}//' )
  _label=$( echo "$_label" |sed -E 's/DONALD VANN /DONALD /' )

  # Returns the formatted label.
  echo $_label
}

# usage: matchRegexp <string> <regular expression>
function matchRegexp() {
  # [[ "$1" =~ "$2" ]] should work but it is no more the case ...
  [ $( echo "$1" |grep "$2" |wc -l ) -eq 1 ]
}

# usage: extractInformation <input as text> <tmpfile>
function extractInformation() {
  local _inputFile="$1"
  local _tmpFile="$2"
  local _MODE_DATE=1
  local _MODE_LABEL=2
  local _mode=$_MODE_DATE
  local currentDate="", currentLabel="", currentValue=0

  [ -f "$_tmpFile" ] && rm -f "$_tmpFile"

  for information in $( cat "$_inputFile" |sed -e 's/[ ][*][ ]/ /g;' ); do
    # Checks if it is a date.
    if matchRegexp "$information" "^[0-9][0-9][.][0-9][0-9]$"; then
      # According to the mode (if in label mode, date is ignored).
      [ $_mode -eq $_MODE_LABEL ] && continue

      # Memorizes the date of this new transaction, and updates the mode.
      currentDate=$( echo "$information/$year" |sed -e 's/[.]/\//' )
      currentLabel=""
      currentValue=0
      _mode=$_MODE_LABEL
      continue
    fi

    # Checks if it is a value.
    # N.B.: makes it NOT match if there is E like EUR after the number, like it is the case with Square Enix entries.
    if ! matchRegexp "$information" "[0-9][0-9]*[,][0-9][0-9]EUR" && matchRegexp "$information" "[0-9]*[.]*[0-9]*[,][0-9][0-9]"; then
      # Ensures the mode is label, otherwise there is an error.
      [ $_mode -ne $_MODE_LABEL ] && echo "Label not found !  Information=$information" && exit 3

      # Memorizes the value.
      currentValue=$( echo "$information" |sed -e 's/,/./g;' )

      # Formats the label.
      currentLabel=$( formatLabel "$currentLabel" )

      # Prints information.
      echo "$currentDate;$currentLabel;$currentValue" >> "$_tmpFile"

      # Prepares for next potential transaction.
      _mode=$_MODE_DATE

      continue
    fi

    # Updates the label.
    currentLabel="$currentLabel $information"
  done

  transactionCount=$( cat "$_tmpFile" |wc -l )

  echo "$transactionCount transactions extracted to $_tmpFile"

  [ $DEBUG -ge 1 ] && echo -e $( cat "$_tmpFile" |sed -e 's/;-\([0-9.]*\)$/;\\E[37;41m-\1\\E[0m\\n/g;s/;+\([0-9.]*\)$/;+\1\\n/g;' )
}

# usage: toQIFFormat <input as text> <output QIF file>
# <output QIF file> can be empty for print on standard output.
function toQIFFormat() {
  local _inputFile="$1"
  local _output="$2"

  echo "These transaction will be ignored:"
  grep -E "$EXCLUDE_PATTERN" "$_inputFile"

  ( echo '!Type:Bank'; cat "$_inputFile" |grep -vE "$EXCLUDE_PATTERN" |awk -F';' '{ print "D" $1; print "P" $2; print "T" $3; print "^"; }' ) > "$_output"

  echo "Transactions information converted to QIF format to $_output"
}

#####################################################
#                Instructions
#####################################################

! convertInputFile "$input" "$textFile" && echo "Error while converting input file" >&2 && exit 2
manageValue "$textFile" "$tmpFile1"
extractInformation "$tmpFile1" "$tmpFile2"
[ ! -z "$output" ] && toQIFFormat "$tmpFile2" "$output"
