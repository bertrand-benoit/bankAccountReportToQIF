#!/bin/bash
#
# Author: Bertrand Benoit <mailto:contact@bertrand-benoit.net>
# Version: 3.1
# Description: converts bank account report (in pdf) to QIF format.
#
# Cf QIF documentation: https://en.wikipedia.org/wiki/Quicken_Interchange_Format
#
# usage: see usage function

export CATEGORY="qifConvert"

currentDir=$( dirname "$( command -v "$0" )" )
export GLOBAL_CONFIG_FILE="$currentDir/default.conf"
export CONFIG_FILE="${HOME:-/home/$( whoami )}/.config/bankReportToQIF.conf"

scriptsCommonUtilities="$currentDir/scripts-common/utilities.sh"
[ ! -f "$scriptsCommonUtilities" ] && echo -e "ERROR: scripts-common utilities not found, you must initialize your git submodule once after you cloned the repository:\ngit submodule init\ngit submodule update" >&2 && exit 1
# shellcheck disable=1090
. "$scriptsCommonUtilities"

# Ensures third-party tools are installed.
checkBin pdftotext || errorMessage "This tool requires pdftotext. Install it please, and then run this tool again."

#####################################################
#                Configuration
#####################################################

textFile="$DEFAULT_TMP_DIR/bankReportToQIF-tmp"
tmpFile1="$textFile.tmp1"
tmpFile2="$textFile.tmp2"
DEFAULT_YEAR=$( date "+%Y" )
DEBUG=0

## Reads some configuration.
# Account Name and type.
checkAndSetConfig "config.account.name" "$CONFIG_TYPE_OPTION"
ACCOUNT_NAME="$LAST_READ_CONFIG"
checkAndSetConfig "config.account.type" "$CONFIG_TYPE_OPTION"
ACCOUNT_TYPE="$LAST_READ_CONFIG"

# Threshold to define if this is a positive or negative amount.
checkAndSetConfig "config.defaultThresholdOfPositiveAmount" "$CONFIG_TYPE_OPTION"
DEFAULT_THRESHOLD_POSITIVE_AMOUNT="$LAST_READ_CONFIG"
checkAndSetConfig "config.tooMuchPositiveAmountWarningThreshold" "$CONFIG_TYPE_OPTION"
TOO_MUCH_POSITIVE_AMOUNT_WARNING_THRESHOLD="$LAST_READ_CONFIG"

## Defines various matching patterns.
checkAndSetConfig "patterns.debitNCreditHeader" "$CONFIG_TYPE_OPTION"
DEBIT_CREDIT_PATTERN="$LAST_READ_CONFIG"
checkAndSetConfig "patterns.transactionLine" "$CONFIG_TYPE_OPTION"
TRANSACTION_LINE_PATTERN="$LAST_READ_CONFIG"
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

## Defines configured dynamic mapping.
loadConfigKeyValueList "map[.]account[.].*" "map[.]account[.]"
declare -n ACCOUNT_MAPPING_KEY_VALUE_LIST="LAST_READ_CONFIG_KEY_VALUE_LIST"

#####################################################
#                Defines usages.
#####################################################
function usage {
  echo -e "BNP Bank PDF Account Report Converter to QIF format, version 3.1."
  echo -e "usage: $0 -i|--input <pdf file> [-o|--output <QIF file>] [-y|--year <year>] [--debug <debug level>] [-h|--help]"
  echo -e "<input>\t\tbank report in PDF format"
  echo -e "<output>\tQIF format output file"
  echo -e "<year>\t\tyear to add to transaction (default: $DEFAULT_YEAR)"
  echo -e "<debug level>\tlevel of debugging message"
  echo -e "-h|--help\tshow this help"
}

#####################################################
#                Command line management.
#####################################################

year="$DEFAULT_YEAR"
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
    DEBUG="${1:-0}"
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

  # Replaces any slash(es) to avoid issue.
  sed -i 's@/@ @g;' "$2"
}

# usage: manageValue <input as text> <output as text>
# Adds '+' or '-' character to introduce amount.
function manageValue() {
  local _inputFile="$1"
  local _tmpFile="$2"
  local plusSignCount=0
  local plusSignThreshold="$DEFAULT_THRESHOLD_POSITIVE_AMOUNT"

  [ -f "$_tmpFile" ] && rm -f "$_tmpFile"

  # Manages all information from text file (result of PDF file convert).
  while IFS= read -r informationRaw; do
    # WARNING: in big values, there is a thousand separator; remove it in this case.
    # shellcheck disable=2001
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
    sign="-"
    if [ "$informationLength" -gt $plusSignThreshold ]; then
      sign="+"
      plusSignCount=$((plusSignCount+1))
    fi

    # Updates the potential amount on the line.
    information=$( echo "$information" |sed -e "s/\([0-9]\)[ ]\([0-9,]*\)$/\1\2/;s/\([0-9][0-9]*[,][0-9][0-9]\)$/$sign\1/g" )
    [ "$DEBUG" -ge 3 ] && writeMessage "[manageValue]  => updated information: $information"

    # Writes to the output file.
    echo "$information" >> "$_tmpFile"
  done < <( grep -E "$TRANSACTION_LINE_PATTERN|$DEBIT_CREDIT_PATTERN" "$_inputFile" |grep -vE "${EXCLUDED_PARTS_FROM_REPORT_PATTERN:-NothingToExclude}" \
                              |sed -e 's/USA \([0-9][0-9,]*\)USD+COMMISSION : \([0-9][0-9,]*\)/USA_COMMISSION/g;' \
                              |sed -E 's/[0-9],[0-9]{2}[ ]E.*TVA[ ]*=[ ]*[0-9]{2},[0-9]{2}[ ]%//' |sed -e 's/[ ]\([.,]\)[ ]/\1/g;' )

  [ $plusSignCount -gt "$TOO_MUCH_POSITIVE_AMOUNT_WARNING_THRESHOLD" ] && warning "There may have too much positive/incoming amount after convert (current Threshold=$plusSignCount). You may check if this is a normal situation."
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
      [ "$DEBUG" -ge 3 ] && writeMessage "[extractInformation][mode=$_mode] Found a date in: $information"
      # According to the mode (if in label mode, date is ignored).
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

  if [ ! -f "$_tmpFile" ]; then
    writeMessage "No transaction extracted to $_tmpFile"
    return 1
  fi

  transactionCount=$( wc -l < "$_tmpFile" )
  writeMessage "$transactionCount transactions extracted to $_tmpFile"

  [ "$DEBUG" -ge 1 ] && writeMessage "$( sed -e 's/;-\([0-9.]*\)$/;\\E[37;41m-\1\\E[0m/g;s/;+\([0-9.]*\)$/;+\1/g;' < "$_tmpFile" )"
  return 0
}

# Extracts transaction account for specified label, according to configuration if any.
# usage: extractTransactionAccount <transaction label>
function extractTransactionAccount() {
  local _transactionLabel=${1,,}

  # Checks if there is a key mapping on lowercase version of specified label.
  for accountMappingKey in "${!ACCOUNT_MAPPING_KEY_VALUE_LIST[@]}"; do
    # If so, returns the corresponding configured account.
    [[ "$_transactionLabel" =~ $accountMappingKey ]] && echo "${ACCOUNT_MAPPING_KEY_VALUE_LIST[$accountMappingKey]}" && return 0
  done

  # Not found but ensures to exit with no error status.
  return 0
}

# usage: toQIFFormat <input as text> <output QIF file>
# <output QIF file> can be empty for print on standard output.
function toQIFFormat() {
  local _inputFile="$1"
  local _output="$2"

  # Informs.
  if [ "$DEBUG" -ge 1 ]; then
    writeMessage "These transaction(s) will be ignored:"
    grep --silent -E "$EXCLUDED_TRANSACTION_PATTERN" "$_inputFile" || writeMessage "<none>"
  fi

  # Cleans output file if needed.
  rm -f "$_output"

  # Adds account name and type, if defined.
  [ -n "$ACCOUNT_NAME" ] && echo -e "!Account\nN$ACCOUNT_NAME\n^" > "$_output"
  [ -n "$ACCOUNT_TYPE" ] && echo -e "!$ACCOUNT_TYPE" >> "$_output"

  # Adds all - not excluded - transactions.
  while IFS=';' read -r transactionDate transactionLabel transactionAmount; do
    # Checks if there is an account mapping matching this label.
    transactionAccount=$( extractTransactionAccount "$transactionLabel" )
    if [ -n "$transactionAccount" ]; then
      printf "L%s\n" "$transactionAccount" >> "$_output"
    else
      [ "$DEBUG" -ge 1 ] && printf "DEBUG: No account mapping for transaction: %s\t%s\t%s\n" "$transactionDate" "$transactionAmount" "$transactionLabel"
    fi

    printf "D%s\nP%s\nT%s\n^\n" "$transactionDate" "$transactionLabel" "$transactionAmount" >> "$_output"
  done < <( grep -vE "${EXCLUDED_TRANSACTION_PATTERN:-NothingToExclude}" "$_inputFile" )

  writeMessage "Transactions information converted to QIF format to $_output"
  return 0
}

#####################################################
#                Instructions
#####################################################

CATEGORY="qif-PdfConvert"
writeMessage "Starting convert from PDF file '$input' ..."
! convertInputFile "$input" "$textFile" && errorMessage "Error while converting input file"

CATEGORY="qif-ManageValue"
manageValue "$textFile" "$tmpFile1"

CATEGORY="qif-ExtractInformation"
extractInformation "$tmpFile1" "$tmpFile2" || exit 1

CATEGORY="qif-WriteFile"
[ -n "${output:-}" ] && toQIFFormat "$tmpFile2" "$output"
exit 0
