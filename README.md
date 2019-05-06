# Bank Account Report To QIF Converter version 3.0.0
This is a free tool allowing to convert Bank PDF Account reports to QIF files.

This script uses my [scripts-common](https://github.com/bertrand-benoit/scripts-common) project, you can find on GitHub.


## Requirements
This tool used [pdftotext](https://poppler.freedesktop.org/) which must be priorly installed. It is generally available with your package manager.


## First time you clone this repository
After the first time you clone this repository, you need to initialize git submodule:
```bash
git submodule init
git submodule update
```

This way, [scripts-common](https://github.com/bertrand-benoit/scripts-common) project will be available and you can use this tool.


## Usage
```bash
BNP Bank PDF Account Report Converter to QIF format, version 3.0.
usage: ./bankReportToQIF.sh -i|--input <pdf file> [-o|--output <QIF file>] [-y|--year <year>] [--debug <debug level>] [-h|--help]
<input>		bank report in PDF format
<output>	QIF format output file
<year>		year to add to transaction (default: 2019)
<debug level>	level of debugging message
-h|--help	show this help
```

## Samples
Convert Bank account report of January 2019:
```bash
  ./bankReportToQIF.sh  -i ~/Documents/myBankAccountReports/20190123.pdf -o /tmp/20190123.qif
```

Convert Bank account report of an older year, let's say February 2002:
```bash
  ./bankReportToQIF.sh -y 2002 -i ~/Documents/myBankAccountReports/20020223.pdf -o /tmp/20020223.qif
```

## Contributing
Don't hesitate to [contribute](https://opensource.guide/how-to-contribute/) or to contact me if you want to improve the project.
You can [report issues or request features](https://github.com/bertrand-benoit/scripts-common/issues) and propose [pull requests](https://github.com/bertrand-benoit/scripts-common/pulls).

## Versioning
The versioning scheme we use is [SemVer](http://semver.org/).

## Authors
[Bertrand BENOIT](mailto:contact@bertrand-benoit.net)

## License
This project is under the GPLv3 License - see the [LICENSE](LICENSE) file for details
