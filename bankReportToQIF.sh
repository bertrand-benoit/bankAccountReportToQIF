#!/bin/bash
#
# Author: Bertrand Benoit <mailto:contact@bertrand-benoit.net>
# Version: 3.0
# Description: converts bank account report (in pdf) to QIF format.
#
# Cf QIF documentation: https://en.wikipedia.org/wiki/Quicken_Interchange_Format
#
# usage: see usage function

export VERBOSE=1
export CATEGORY="qifConvert"

currentDir=$( dirname "$( which "$0" )" )
export GLOBAL_CONFIG_FILE="$currentDir/default.conf"
export CONFIG_FILE="${HOME:-/home/$( whoami )}/.config/bankReportToQIF.conf"

. "$currentDir/scripts-common/utilities.sh"

#####################################################
#                Configuration
#####################################################

textFile="$DEFAULT_TMP_DIR/bankReportToQIF-tmp"
tmpFile1="$textFile.tmp1"
tmpFile2="$textFile.tmp2"
DEFAULT_YEAR=$( date "+%Y" )
DEBUG=1

# Threshold to define if this is a positive or negative operation.
# Till May 2016, it was OK with 175; from then this threshold is defined dynamically.
DEFAULT_THRESHOLD_POSITIVE_OPERATION=175

## Defines various matching patterns.
checkAndSetConfig "patterns.debitNCreditHeader" "$CONFIG_TYPE_OPTION"
DEBIT_CREDIT_PATTERN="$LAST_READ_CONFIG"
checkAndSetConfig "patterns.date" "$CONFIG_TYPE_OPTION"
DATE_PATTERN="$LAST_READ_CONFIG"
checkAndSetConfig "patterns.label.amountWithCurrency" "$CONFIG_TYPE_OPTION"
LABEL_AMOUNT_WITH_CURRENCY_PATTERN="$LAST_READ_CONFIG"
checkAndSetConfig "patterns.amount" "$CONFIG_TYPE_OPTION"
AMOUNT_PATTERN="$LAST_READ_CONFIG"

## Defines various exclusion patterns.
checkAndSetConfig "patterns.label.removeMatchingParts" "$CONFIG_TYPE_OPTION"
REMOVE_LABEL_MATCHING_PARTS="$LAST_READ_CONFIG"
checkAndSetConfig "patterns.label.removeAllAfterMatchingParts" "$CONFIG_TYPE_OPTION"
REMOVE_LABEL_PARTS_AFTER_MATCHING="$LAST_READ_CONFIG"

# Bank report exclusion pattern (e.g. some useless bank report information like address ...).
checkAndSetConfig "patterns.excludedPartsFromReport" "$CONFIG_TYPE_OPTION"
EXCLUDED_PARTS_FROM_REPORT_PATTERN="$LAST_READ_CONFIG"

# Transactions exclusion pattern (e.g. some recurrent transaction which are embedded to GNU/Cash).
checkAndSetConfig "patterns.excludedTransactions" "$CONFIG_TYPE_OPTION"
EXCLUDED_TRANSACTION_PATTERN="$LAST_READ_CONFIG"

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
    if matchesOneOf "$information" "$DEBIT_CREDIT_PATTERN"; then
      # Updates the sign threshold according to the position of Credit keyword which is at the end of the line.
      plusSignThreshold=$((informationLength-5))
      [ "$DEBUG" -ge 2 ] && writeMessage "[manageValue] Defined/Updated + sign threshold to $plusSignThreshold ..."
      continue;
    fi

    # Defines the value sign (it is '+' if and only if there is more than <threshold> characters).
    [ "$informationLength" -gt $plusSignThreshold ] && sign="+" || sign="-"
    [ "$sign" = "+" ] && plusSignCount=$((plusSignCount++))

    # Updates the potential value on the line.
    information=$( echo "$information" |sed -e "s/\([0-9]\)[ ]\([0-9,]*\)$/\1\2/;s/\([0-9][0-9]*[,][0-9][0-9]\)$/$sign\1/g" )
    [ "$DEBUG" -ge 3 ] && writeMessage "[manageValue]  => updated information: $information"

    # Writes to the output file.
    echo "$information" >> "$_tmpFile"
  done < <( grep -E "^[ ]{1,3}[0-9]|^[ ]{5,20}[A-Z0-9+*]|$DEBIT_CREDIT_PATTERN" "$_inputFile" |grep -vE "$EXCLUDED_PARTS_FROM_REPORT_PATTERN" \
                              |sed -e 's/USA \([0-9][0-9,]*\)USD+COMMISSION : \([0-9][0-9,]*\)/USA_COMMISSION/g;' \
                              |sed -E 's/[0-9],[0-9]{2}[ ]E.*TVA[ ]*=[ ]*[0-9]{2},[0-9]{2}[ ]%//' |sed -e 's/[ ]\([.,]\)[ ]/\1/g;' )

  [ $plusSignCount -gt 6 ] && warning "it seems there is too much incoming after convert ($plusSignCount)"
  return 0
}

# usage: formatLabel <label>
# The aim is to remove useless information for GNU/Cash to improve accounts matching according to previous import.
function formatLabel() {
  local _label="$1"

  # Removes label's part exactly matching.
  while IFS= read -r -d '|' formatLabelPattern; do
    _label=$( sed -E "s/$formatLabelPattern//;" <<< "$_label" )
  done <<< "$REMOVE_LABEL_MATCHING_PARTS"

  # Cuts label's part AFTER matching.
  while IFS= read -r -d '|' formatLabelPattern; do
    _label=$( sed -E "s/$formatLabelPattern.*$/$formatLabelPattern/;" <<< "$_label" )
  done <<< "$REMOVE_LABEL_PARTS_AFTER_MATCHING"

  # Returns the formatted label.
  echo "$_label"
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

  while IFS= read -r information; do
    # Checks if it is a date.
    if matchesOneOf "$information" "$DATE_PATTERN"; then
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

    # Checks if it is an amount.
    # Warning: ignore information if it contains currency because it means it is still a part of the label.
    if  ! matchesOneOf "$information" "$LABEL_AMOUNT_WITH_CURRENCY_PATTERN" \
       && matchesOneOf "$information" "$AMOUNT_PATTERN"; then
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
  done < <( tr -s '[:blank:]' '[\n*]' < "$_inputFile" )

  # Registers the last line, if any.
  [ "$_mode" != "$_MODE_INITIAL" ] && registerExtractedInformation "$currentDate" "$currentLabel" "$currentValue" "$_tmpFile"

  transactionCount=$( wc -l < "$_tmpFile" )

  writeMessage "$transactionCount transactions extracted to $_tmpFile"

  [ "$DEBUG" -ge 1 ] && writeMessage "$( sed -e 's/;-\([0-9.]*\)$/;\\E[37;41m-\1\\E[0m/g;s/;+\([0-9.]*\)$/;+\1/g;' < "$_tmpFile" )"
  return 0
}

# usage: toQIFFormat <input as text> <output QIF file>
# <output QIF file> can be empty for print on standard output.
function toQIFFormat() {
  local _inputFile="$1"
  local _output="$2"

  writeMessage "These transaction will be ignored:"
  grep --silent -E "$EXCLUDED_TRANSACTION_PATTERN" "$_inputFile"

  echo '!Type:Bank' > "$_output"
  ( grep -vE "$EXCLUDED_TRANSACTION_PATTERN" |awk -F';' '{ print "D" $1; print "P" $2; print "T" $3; print "^"; }' ) < "$_inputFile" >> "$_output"

  writeMessage "Transactions information converted to QIF format to $_output"
  return 0
}

#####################################################
#                Instructions
#####################################################

CATEGORY="qif-PdfConvert"
! convertInputFile "$input" "$textFile" && errorMessage "Error while converting input file"
CATEGORY="qif-ManageValue"
manageValue "$textFile" "$tmpFile1"
CATEGORY="qif-ExtractInformation"
extractInformation "$tmpFile1" "$tmpFile2"
CATEGORY="qif-WriteFile"
[ -n "${output:-}" ] && toQIFFormat "$tmpFile2" "$output"
exit 0
