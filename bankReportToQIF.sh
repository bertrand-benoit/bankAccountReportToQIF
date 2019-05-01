#!/bin/bash
#
# Author: Bertrand Benoit <mailto:contact@bertrand-benoit.net>
# Version: 3.0
# Description: converts bank account report (in pdf) to QIF format.
#
# usage: see usage function

export VERBOSE=1
export CATEGORY="qifConvert"

currentDir=$( dirname "$( which "$0" )" )
. "$currentDir/scripts-common/utilities.sh"

#####################################################
#                Configuration
#####################################################

textFile="$DEFAULT_TMP_DIR/bankReportToQIF-tmp"
tmpFile1="$textFile.tmp1"
tmpFile2="$textFile.tmp2"
DEFAULT_YEAR=$( date "+%Y" )
DEBUG=1

# TODO: nedd to check 2/3 transactions from August Report ... they were as NEGATIVE instead of positive :/

# Threshold to define if this is a positive or negative operation.
# Till May 2016, it was OK with 175; from then this threshold is defined dynamically.
DEFAULT_THRESHOLD_POSITIVE_OPERATION=175

# Transactions exclusion pattern (some recurrent transaction which are embedded to GNU/Cash).
EXCLUDE_PATTERN="PENSION|LOYER|CIRCLE"

# Defines special regexp corresponding to header line with 'Debit' and 'Credit' keywords.
DEBIT_CREDIT_EXP="^.*D[ \t]*[eé]bit.*C[ \t]*r[eé]dit.*$"

# Bank report exclusion pattern (some useless bank report information).
REPORT_EXCLUDE_PATTERN="SOLDE CREDITEUR|SOLDE DEBITEUR|SOLDE AU |TOTAL DES OPERATIONS|Rappel|opérations courante|www.bnpparibas.net|Minitel|code secret|Votre conseiller|tarification|prélévé au début|mois suivant|ce tarif|s'appliquent|conseiller|bénéficiez|carte à débit|Conseiller en agence|Commissions sur services|de votre autorisation|Médiateur|TAEG|saisine"

#####################################################
#                Defines usages.
#####################################################
function usage {
  echo -e "BNP PDF Report Converter to QIF format, version 3.0."
  echo -e "usage: $0 -i|--input <pdf file> [-o|--output <QIF file>] [-y|--year <year>] [--debug <debug level>] [-h|--help]"
  echo -e "-h|--help\tshow this help"
  echo -e "<input>\t\tbank report in PDF format"
  echo -e "<output>\tQIF format output file"
  echo -e "<year>\t\tyear to add to transaction (default: $DEFAULT_YEAR)"
  echo -e "<debug level>\tlevel of debugging message"
}

#####################################################
#                Command line management.
#####################################################

year=$DEFAULT_YEAR
while [ -n "${1:-}" ]; do
  if [ "$1" == "-i" ] || [ "$1" = "--input" ]; then
    shift
    input="$1"
  elif [ "$1" == "-o" ] || [ "$1" = "--output" ]; then
    shift
    output="$1"
  elif [ "$1" == "-y" ] || [ "$1" = "--year" ]; then
    shift
    year="$1"
  elif [ "$1" = "--debug" ]; then
    shift
    DEBUG="$1"
  elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage && exit 0
  else
    usage
    errorMessage "Unknown parameter '$1'"
  fi

  shift
done

[ -z "${input:-}" ] && usage && errorMessage "You must specify input file"
[ ! -f "${input:-}" ] && usage && errorMessage "Specified input file '$input' must exist"

[ -n "${output:-}" ] && [ -f "${output:-}" ] && usage && errorMessage "Specified output file '$output' must NOT exist"

#####################################################
#                Functions
#####################################################

# usage: convertInputFile <input as PDF> <output as text>
function convertInputFile() {
  [ "$DEBUG" -ge 2 ] && writeMessage "DEBUG: converting $1 to $2"
  pdftotext -layout "$1" "$2" 2>/dev/null

  # Replaces any slash to avoid issue.
  sed -i 's@/@ @g;' "$2"

  # In some unknown situations, there is more than one space characters (2 or 3) at the beginning of important lines ...
  #  ensures there is only one.
  #sed -i 's/^[ ][ ]\([0-9]\)/ \1/;s/^[ ][ ][ ]\([0-9]\)/ \1/;' "$2"
}

# usage: manageValue <input as text> <output as text>
# Adds '+' or '-' character to introduce value.
function manageValue() {
  local _inputFile="$1"
  local _tmpFile="$2"

  [ -f "$_tmpFile" ] && rm -f "$_tmpFile"

  # Information:
  #  - until banq report of 09/2012, there was always between 5 and 14 space characters; since then, there can be 16 ...
  #  - since SEPA information, so about ??/2013, there can be 17 space characters ...
  plusSignCount=0
  plusSignThreshold=$DEFAULT_THRESHOLD_POSITIVE_OPERATION

  while IFS= read -r informationRaw; do
    # WARNING: in big values, there is a thousand separator; remove it in this case.
    information=$( echo "$informationRaw" |sed -e "s/\([0-9][0-9]*\)[.]\([0-9][0-9]*[,][0-9][0-9]\)$/\1\2/g;" )
    informationLength="${#information}"
    [ "$DEBUG" -ge 3 ] && writeMessage "[manageValue] Working on information (length=$informationLength): $information"

    # Checks if this is a header line (one per page) with credit/debit keywords.
    if matchRegexp "$information" "$DEBIT_CREDIT_EXP"; then
      # Updates the sign threshold according to the position of Credit keyword which is at the end of the line.
      plusSignThreshold=$((informationLength-5))
      [ "$DEBUG" -ge 2 ] && writeMessage "[manageValue] Defined/Updated + sign threshold to $plusSignThreshold ..."
      continue;
    fi

    # Defines the value sign (it is '+' if and only if there is more than <threshold> characters).
    [ "$informationLength" -gt $plusSignThreshold ] && sign="+" || sign="-"
    [ "$sign" = "+" ] && let plusSignCount++

    # Updates the potential value on the line.
    information=$( echo "$information" |sed -e "s/\([0-9]\)[ ]\([0-9,]*\)$/\1\2/;s/\([0-9][0-9]*[,][0-9][0-9]\)$/$sign\1/g" )
    [ "$DEBUG" -ge 3 ] && writeMessage "[manageValue]  => updated information: $information"

    # Writes to the output file.
    echo "$information" >> "$_tmpFile"
  done < <( grep -E "^[ ]{1,3}[0-9]|^[ ]{5,20}[A-Z0-9+*]|$DEBIT_CREDIT_EXP" "$_inputFile" |grep -vE "$REPORT_EXCLUDE_PATTERN" \
                              |sed -e 's/USA \([0-9][0-9,]*\)USD+COMMISSION : \([0-9][0-9,]*\)/USA_COMMISSION/g;' \
                              |sed -E 's/[0-9],[0-9]{2}[ ]E.*TVA[ ]*=[ ]*[0-9]{2},[0-9]{2}[ ]%//' |sed -e 's/[ ]\([.,]\)[ ]/\1/g;' )

  [ $plusSignCount -gt 6 ] && warning "it seems there is too much incoming after convert ($plusSignCount)"
}

# usage: formatLabel <label>
function formatLabel() {
  local _label="$1"

  # The aim is to remove useless information for GNU/Cash to match corresponding
  #  accounts from previous import.

  # Removes useless "date info." and "SEPA info" from label.
  _label=$( echo "$_label" |sed -E 's/DU [0-9]{6}[ ]//g;s/FACTURE.S.[ ]CARTE[ ]4974XXXXXXXX[0-9]{4}[ ]//g;s/NUM[ ][0-9]{6}[ ]ECH.*$//g;' )
  _label=$( echo "$_label" |sed -E 's/ECH[ ][0-9]{6}[ ][ID ]{0,3}//g;' )
  _label=$( echo "$_label" |sed -E 's/EMETTEUR.*LIB/- /' )
  _label=$( echo "$_label" |sed -E 's/RETRAIT DAB [0-9\/ ]{8}[ ][0-9Hh]{5}.*/RETRAIT DAB /g;s/C.P.A.M..*$/C.P.A.M./' )
  _label=$( echo "$_label" |sed -E 's/[0-9]{0,}FRAIS SANTE[ ][0-9].*$/SANTE/;s/VTL[ ][0-9]{2}\/[0-9]{2}[ ][0-9]{2}[hH][0-9]{2}[ ]V[0-9]{1,}//' )
  _label=$( echo "$_label" |sed -E 's/VIR SEPA RECU DE/VIR/;s/VRST ESPECES/VIR ESPECES/;s/PRLV SEPA //' )
  _label=$( echo "$_label" |sed -e 's/^\(.*\)[ ]MOTIF.*$/\1/' )
  _label=$( echo "$_label" |sed -E 's/DONALD VANN /DONALD /' )

  # Special management.
  for specialLabelPart in "PAYPAL" "VIR ESPECES" "FREE MOBILE" "D.G.F.I.P. IMPOT" "ACM-IARD SA" "AVIVA ASSURANCE" "VOTRE ABONNEMENT INTERNET" "GIE AFER" \
    "VIR ASTON ITRADE FINANCE" "E.LECLERC" "DEICHMANN NANCY" "MC DONALD"; do
    _label=$( echo "$_label" |sed -E "s/$specialLabelPart.*$/$specialLabelPart/" )
  done

  # Returns the formatted label.
  echo "$_label"
}

# usage: matchRegexp <string> <regular expression>
function matchRegexp() {
  #[[ "$1" =~ "$2" ]] should work but it is no more the case ...
  [ "$( echo "$1" |grep -c "$2" )" -eq 1 ]
}

# usage: registerExtractedInformation <currentDate> <label> <value> <file>
function registerExtractedInformation() {
    local _currentDate="$1" _currentLabel="$2" _currentValue="$3"
    local _tmpFile="$4"

    # Formats the label.
    _currentLabel=$( formatLabel "$_currentLabel" )

    # Prints information.
    local _line="$_currentDate;$_currentLabel;$_currentValue"
    [ "$DEBUG" -ge 2 ] && writeMessage "[extractInformation][mode=$_mode] Registering extracted and formatted data: $_line"
    echo "$_line" >> "$_tmpFile"
}

# usage: extractInformation <input as text> <tmpfile>
function extractInformation() {
  local _inputFile="$1"
  local _tmpFile="$2"
  local _MODE_INITIAL=1
  local _MODE_LABEL=2
  local _MODE_LABEL_EXTRA=3
  local _mode=$_MODE_INITIAL
  local currentDate="", currentLabel="", labelSeparator="", currentValue=0

  [ -f "$_tmpFile" ] && rm -f "$_tmpFile"

  for information in $( cat "$_inputFile" |sed -e 's/[ ][*][ ]/ /g;' ); do
    # Checks if it is a date.
    if matchRegexp "$information" "^[0-9][0-9][.][0-9][0-9]$"; then
      # According to the mode (if in label mode, date is ignored).
      [ "$DEBUG" -ge 3 ] && writeMessage "[extractInformation][mode=$_mode] Found a date in: $information"
      [ $_mode -eq $_MODE_LABEL ] && continue

      # A new date has been found, and we are not managing label, so considering we reach a new line.
      # N.B.: this new system allows to complete label with extra information till next date is found, or end
      #  of report is reached.
      [ "$_mode" != "$_MODE_INITIAL" ] && registerExtractedInformation "$currentDate" "$currentLabel" "$currentValue" "$_tmpFile"

      # Memorizes the date of this new transaction, and updates the mode.
      currentDate=$( echo "$information/$year" |sed -e 's/[.]/\//' )

      # Resets all other variables.
      currentLabel=""
      labelSeparator=""
      currentValue=0
      _mode=$_MODE_LABEL
      continue
    fi

    [ "$DEBUG" -ge 3 ] && writeMessage "[extractInformation][mode=$_mode] Working on information: $information"

    # Checks if it is a value.
    # N.B.: makes it NOT match if there is E like EUR after the number, like it is the case with Square Enix entries.
    if ! matchRegexp "$information" "[0-9][0-9]*[,][0-9][0-9]EUR" \
       && matchRegexp "$information" "[0-9]*[.]*[0-9]*[,][0-9][0-9]"; then
      # Ensures the mode is label or label extra, otherwise there is an error.
      [ $_mode -ne $_MODE_LABEL ] && [ $_mode -ne $_MODE_LABEL_EXTRA ] && echo "Label not found !  Information=$information (check $_tmpFile)" && exit 3

      # Memorizes the value.
      currentValue="${information//,/.}"

      # Prepares for next potential transaction.
      _mode=$_MODE_LABEL_EXTRA

      continue
    fi

    # Updates the label.
    currentLabel="$currentLabel$labelSeparator$information"
    labelSeparator=" "
  done

  # Registers the last line, if any.
  [ "$_mode" != "$_MODE_INITIAL" ] && registerExtractedInformation "$currentDate" "$currentLabel" "$currentValue" "$_tmpFile"

  transactionCount=$( wc -l < "$_tmpFile" )

  writeMessage "$transactionCount transactions extracted to $_tmpFile"

  [ "$DEBUG" -ge 1 ] && writeMessage "$( sed -e 's/;-\([0-9.]*\)$/;\\E[37;41m-\1\\E[0m/g;s/;+\([0-9.]*\)$/;+\1/g;' < "$_tmpFile" )"
}

# usage: toQIFFormat <input as text> <output QIF file>
# <output QIF file> can be empty for print on standard output.
function toQIFFormat() {
  local _inputFile="$1"
  local _output="$2"

  writeMessage "These transaction will be ignored:"
  grep -E "$EXCLUDE_PATTERN" "$_inputFile"

  echo '!Type:Bank' > "$_output"
  ( grep -vE "$EXCLUDE_PATTERN" |awk -F';' '{ print "D" $1; print "P" $2; print "T" $3; print "^"; }' ) < "$_inputFile" >> "$_output"

  writeMessage "Transactions information converted to QIF format to $_output"
}

#####################################################
#                Instructions
#####################################################

! convertInputFile "$input" "$textFile" && errorMessage "Error while converting input file"
manageValue "$textFile" "$tmpFile1"
extractInformation "$tmpFile1" "$tmpFile2"
[ -n "${output:-}" ] && toQIFFormat "$tmpFile2" "$output"
