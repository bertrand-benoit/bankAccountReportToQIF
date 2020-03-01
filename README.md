:warning: This project is now hosted on [Gitlab](https://gitlab.com/bertrand-benoit/bankAccountReportToQIF); switch to it to get newer versions.

# Bank Account Report To QIF Converter version 3.1.0

[![Codacy Badge](https://api.codacy.com/project/badge/Grade/b9d06cb55eea4e1d8a20da784e7f2f92)](https://app.codacy.com/app/bertrand-benoit/bankAccountReportToQIF?utm_source=github.com&utm_medium=referral&utm_content=bertrand-benoit/bankAccountReportToQIF&utm_campaign=Badge_Grade_Dashboard)

This is a free tool allowing to convert Bank PDF Account reports to QIF files.

This script uses my [scripts-common](https://gitlab.com/bertrand-benoit/scripts-common) project.

## Requirements
This tool used [pdftotext](https://poppler.freedesktop.org/) which must be priorly installed. It is generally available with your package manager.

## First time you clone this repository
After the first time you clone this repository, you need to initialize git submodule:
```bash
git submodule init
git submodule update
```

This way, [scripts-common](https://gitlab.com/bertrand-benoit/scripts-common) project will be available and you can use this tool.

## Configuration files
This tools uses the configuration file feature of the [scripts-common](https://gitlab.com/bertrand-benoit/scripts-common) project.

The global configuration file, called **default.conf**, is in the root directory of this repository.
It contains default configuration for this tool, and should NOT be edited.

You can/should create your own configuration file **~/.config/bankReportToQIF.conf** and override any value you want to adapt output QIF to your needs.

### User configuration file sample
This is a example of an user configuration file
```bash
## Defines various configuration.
config.account.name="Actif:Actifs actuels:Compte cheques"

## Defines various patterns.
patterns.excludedPartsFromReport="BNP Paribas|bnpparibas.net|TOTAL DES OPERATIONS|SOLDE CREDITEUR|SOLDE DEBITEUR|Minitel|code secret|Votre conseiller|éclamation|Médiateur|votre numéro client|opérations courante|Commissions sur services|de votre autorisation|le TAEG effectif|La tarification|e tarif"
patterns.label.removeMatchingParts=""

## Defines various dynamic account mapping.
# Finances.
map.account.dgfip impot th="Depenses:Intérets Taxes Impôts:Impôts"
map.account.d.g.f.i.p="Depenses:Intérets Taxes Impôts:Impôts"
map.account.retrait dab="Depenses:Divers:Retrait distributeur"

# Démarches administratives CNI, Passport ...
map.account.photomaton saint denis="Depenses:Divers:Administratifs"
map.account.timbre fiscal="Depenses:Divers:Administratifs"

# Santé.
map.account.c.p.a.m.="Revenus:Divers:Remboursement:CPAM (Securite sociale)"
map.account.dr bainville="Depenses:Dépenses médicales:Ostéopathe"
map.account.atoutbio="Depenses:Dépenses médicales:Remboursés:Médecins, Hopitaux, Cliniques ..."
map.account.pharma="Depenses:Dépenses médicales:Remboursés:AvanceMedicaments"
map.account.phie="Depenses:Dépenses médicales:Remboursés:AvanceMedicaments"

# Numérique.
map.account.www.aliexpress="Depenses:Informatique et Numérique"
map.account.paypal="Depenses:Informatique et Numérique"
map.account.amazon="Depenses:Informatique et Numérique"

# Loisirs.
map.account.kinep="Depenses:Tourisme, Vacances, Sorties ...:Cinéma"
map.account.cinema="Depenses:Tourisme, Vacances, Sorties ...:Cinéma"
map.account.ugc="Depenses:Tourisme, Vacances, Sorties ...:Cinéma"
map.account.bowling="Depenses:Tourisme, Vacances, Sorties ..."
map.account.lasermaxx="Depenses:Tourisme, Vacances, Sorties ..."
map.account.mini golf="Depenses:Tourisme, Vacances, Sorties ..."
map.account.hall du livre="Depenses:Tourisme, Vacances, Sorties ..."

map.account.decathlon="Depenses:Divers:Activités sportives"
map.account.ovive="Depenses:Divers:Activités sportives"
map.account.nancy thermal="Depenses:Divers:Activités sportives"

# Abonnement logement, énergie ...
map.account.abonnement internet="Depenses:Abonnements:Internet"
map.account.abonnement mobile="Depenses:Abonnements:Téléphone Portable"
map.account.edf="Depenses:Abonnements:EDF-GDF:EDF"

# Courses.
map.account.lidl="Depenses:Alimentaire:Lidl"
map.account.cora .. hyper="Depenses:Alimentaire:Cora"
map.account.cora .. interne="Depenses:Alimentaire:Cora"
map.account.cora toul="Depenses:Alimentaire:Cora"
map.account.carrefour="Depenses:Alimentaire:Carrefour"
map.account.e.leclerc="Depenses:Alimentaire:Leclerc"
map.account.intermarche="Depenses:Alimentaire:Intermarché"
map.account.auchan laxou="Depenses:Alimentaire:Autre"
map.account.colruyt="Depenses:Alimentaire:Autre"

map.account.lor n bio="Depenses:Alimentaire:MagasinBIO"
map.account.natureo="Depenses:Alimentaire:MagasinBIO"
map.account.naturalia="Depenses:Alimentaire:MagasinBIO"
map.account.atout vrac="Depenses:Alimentaire:MagasinBIO"
map.account.la vie claire="Depenses:Alimentaire:MagasinBIO"

# Transport (carburant, train ...)
map.account.cora to carbura="Depenses:Transports divers:Vehicule"
map.account.cora to station="Depenses:Transports divers:Vehicule"
map.account.super u="Depenses:Transports divers:Vehicule"
map.account.horodateur="Depenses:Transports divers:Vehicule"
map.account.indigo="Depenses:Transports divers:Vehicule"

map.account.shell="Depenses:Transports divers:Vehicule"
map.account.auchan carburan="Depenses:Transports divers:Vehicule"
map.account.auchan essence="Depenses:Transports divers:Vehicule"
map.account.carrefourstatio="Depenses:Transports divers:Vehicule"

map.account.aprr="Depenses:Transports divers:Vehicule"
map.account.feu vert="Depenses:Transports divers:Vehicule"

map.account.sncf="Depenses:Transports divers:Train"

map.account.keolis="Depenses:Transports divers:Divers"
map.account.ratp="Depenses:Transports divers:Divers"
map.account.transdev="Depenses:Transports divers:Divers"

# Boulangerie.
map.account.battavoine="Depenses:Restaurant:Boulangerie"
map.account.boul. baudet="Depenses:Restaurant:Boulangerie"
map.account.boul pati rene="Depenses:Restaurant:Boulangerie"
map.account.pain et gateau="Depenses:Restaurant:Boulangerie"
map.account.paul="Depenses:Restaurant:Boulangerie"
map.account.brioche dorees="Depenses:Restaurant:Boulangerie"
map.account.vanille chocola="Depenses:Restaurant:Boulangerie"

# Restaurant.
map.account.fetch="Depenses:Restaurant"
map.account.spezia="Depenses:Restaurant"
map.account.burger king="Depenses:Restaurant"
map.account.le 167="Depenses:Restaurant"
map.account.le voyou="Depenses:Restaurant"
map.account.angeluzzo="Depenses:Restaurant"
map.account.cerise="Depenses:Restaurant"
map.account.line wok="Depenses:Restaurant"
map.account.arrosoir="Depenses:Restaurant"
```

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
You can [report issues or request features](https://gitlab.com/bertrand-benoit/bankAccountReportToQIF/issues) and propose [merge requests](https://gitlab.com/bertrand-benoit/bankAccountReportToQIF/merge_requests).

## Versioning
The versioning scheme we use is [SemVer](http://semver.org/).

## Authors
[Bertrand BENOIT](mailto:contact@bertrand-benoit.net)

## License
This project is under the GPLv3 License - see the [LICENSE](LICENSE) file for details
