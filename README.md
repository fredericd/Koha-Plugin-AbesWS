# Plugin AbesWS

**AbesWS** est un plugin Koha qui permet d'exploiter depuis Koha des services
web de l'Abes. L'intégration à Koha de services web de l'Abes vise deux
objectifs distincts et complémentaires :

- **Enrichissement de l'affichage** — L'affichage des notices dans Koha est
  enrichi de données récupérées en temps réel à l'Abes.

- **Contrôles rétrospectifs** — Des listes d'anomalies de catalogage sont
  affichées. À partir de ces listes, des opérations de correction peuvent être
  lancées.

## Installation

**Activation des plugins** — Si ce n'est pas déjà fait, dans Koha, activez les
plugins. Demandez à votre prestataire Koha de le faire, ou bien vérifiez les
points suivants :

- Dans `koha-conf.xml`, activez les plugins.
- Dans le fichier de configuration d'Apache, définissez l'alias `/plugins`.
  Faites en sorte que le répertoire pointé ait les droits nécessaires.

**📁 TÉLÉCHARGEMENT** — Récupérez sur le site [Tamil](https://www.tamil.fr)
l'archive de l'Extension
**[AbesWS](https://www.tamil.fr/download/koha-plugin-abesws-1.0.6.kpz)**.

Dans l'interface PRO de Koha, allez dans `Outils > Outils de Plugins`. Cliquez
sur Télécharger un plugin. Choisissez l'archive **téléchargée** à l'étape
précédente. Cliquez sur Télécharger.

Le plugin utilise par ailleurs deux modules Perl qu'on ne trouve pas en
standard avec Koha : `MARC::Moose` et `Pithub::Markdown`. Il faut les installer
sur votre serveur Koha.

## Utilisation du plugin

### Configuration

Dans les Outils de plugins, vous voyez l'Extension *AbesWS*. Cliquez sur
Actions > Configurer.

Plusieurs sections pilotent le fonctionnement du plugin :

- **Accès aux WS** — Paramètres d'accès aux services web. Il n'est pas
  nécessaire de modifier les paramètres par défaut. Précisions pour IdRef:
  - **URL IdRef** — L'URL du point d'accès à IdRef. Par défaut
    `https://www.idref.fr`. En phase de test, on peut obtenir de l'Abes une
    autre URL.
  - **ID Client** — Identifiant de l'établissement utilisant les services web
    de l'Abes. Cet identifiant permet à l'Abes de tenir à jour des statistiques
    d'usage de ses services par établissement.

- **Établissement** — L'ILN et les RCR de l'ILN. Les services web
  _bibliocontrol_ et _AlgoLien_ ne seront interrogés que pour cet ILN et ces
  RCR. Pour les RCR, il faut entrer la liste de ses RCR, suivi pour chacun du
  nom en clair de la bibliothèque. Par exemple :

  ```text
  341722102 BIU Montpellier - Droit, Science po, Eco et Gestion
  341725201 Abes - Centre de doc
  ```

  permettra d'interroger les infos relatives à deux RCR, le RCR 341722102
  correspond à la _BIU Montpellier - Droit, Science po, Eco et Gestion_ et le
  RCR 341725201 pour _Abes - Centre de doc_.

  Notez qu'on peut utiliser le plugin sans être déployé dans le Sudoc.
  Certaines fonctionnalités de controle ne seront pas opérantes : bibliocontrol
  et AlgoLien.

- **bibliocontrol** — Le service web _bibliocontrol_ renvoie les anomalies de
  catalogage d'un ou de plusieurs RCR choisis dans la liste définie dans la
  section _Etablissement_. Ces anomalies sont, pour le moment, au nombre de trois :

  - Présence d'une zone 225 esseulée
  - Code fonction 000 en 700, 701 ou 702
  - Présence simultanée d'une zone 181 et d'une sous-zone 200$b

  On choisit ici les anomalies à afficher.

- **PRO Page détail** — Dans la page détail d'une notice bibliographique
  affichée dans l'interface PRO de Koha, on peut récupérer et afficher des
  informations complémentaires obtenues au moyen des services web de l'Abes.
  Pour le moment, on dispose des options suivantes :

  - **Activer** — pour activer l'affichage d'infos provenant du Sudoc sur la
    page de détail des notices biblio
  - **Localisation** — pour afficher les localisations de la notice dans les
    établissements déployés dans le Sudoc.
  - **Sélecteur PPN** — Sélecteur jQuery permettant de retrouver le PPN dans la
    page de détail. C'est la feuille de style XSL de la page de détail de
    l'interface pro qui affiche et rend accessible le PPN. Par exemple,
    `#ppn_value`.
  - **QualiMarc** — Analyse de la notice avec
    [QualiMarc](https://qualimarc.sudoc.fr), l'outil d'analyse des notices
    bibliographiques du Sudoc.
  - **Analyse** — Niveau d'analyse QualiMarc, rapide ou complète.

- **IdRef PRO Catalogage** — Fonctionnement du plugin dans la page de catalogage de
  Koha:
  - **Activer** — Bascule permettant d'activer/désactiver l'utilisation de
    IdRef en catalogage.
  - **Champs** — La liste des champs pour lesquels le lien à IdRef est établi.
    Le lien aux zones 7xx est pleinement fonctionnel. Pour les zones Rameau
    (6xx), ce n'est pas encore totalement le cas.

- **IdRef OPAC Détail** — Permet d'activer l'affichage sur la page de
  détail de l'OPAC d'infos supplémentaires sur les auteurs et les
  collectivités.

### Bibliocontrol

La page **bibliocontrol** lance l'appel au service web bibliocontrol de l'Abes,
puis affiche le résultat dans un tableau. On choisit au préalable le RCR dont on
veut contrôler les notices. Le tableau contient deux colonnes permettant
d'identifier les notices : PPN et Titre.

La colonne Titre contient le titre de la notice si le plugin peut le retrouver
dans Koha à partir du PPN. Pour que cela fonctionne, il faut avoir établi un
lien dans `Administration > Liens Koha => MARC` entre le champ Unimarc contenant
le PPN et le champ MySQL `biblioitems.lccn`.

La colonne PPN contient une icône permettant de copier d'un clic le PPN dans le
presse-papier. De là, on peut passer dans _WinIBW_ pour retrouver une notice et
la modifier.

### AlgoLiens

**AlgoLiens** est un service web de l'Abes qui, pour un ou plusieurs RCR,
identifie les notices présentant des zones pour lesquelles il manque les
sous-zones de liens. C'est par exemple une zone comme celle-ci :

```text
702  1 $a Arbus $b Sanson $4 610
```

qui n'a pas de sous-zone `$3` établissant un lien avec une autorité Auteur.

Sur la page de démarrage, on sélectionne le/les RCR ainsi que les types de
notice que l'on souhaite contrôler. On distingue les notices bibliographiques
des notices d'autorité. Pour chaque notice, on peut choisir des types de
document ou des types d'autorité.

Un tableau présente le résultat obtenu au moyen de l'appel du service web
AlgoLiens.

### PRO Détail

On active cette fonctionnalité dans la page de configuration du plugin. Le
paramètre **Sélecteur PPN** doit être renseigné. Il permet au plugin de
localiser le PPN sur la page de détail. La feuille de style XSL d'affichage
doit être adaptée en conséquence. Par exemple, si on a le PPN dans le tag 009
et si on définit un sélecteur PPN **#ppn_value**, la feuille de style devra
contenir quelque chose qui ressemble à ceci :

```xml
<xsl:if test="marc:controlfield[@tag=009]">
  <span class="results_summary tag_009">
    <span class="label">Champ 009 : </span>
    <span id="ppn_value">
      <xsl:value-of select="marc:controlfield[@tag=009]"/>
    </span>
  </span>
</xsl:if>
```

**Localisation** — Si on a activé l'affichage des localisations Sudoc, le
service web _multiwhere_ de l'Abes est appelé pour chaque notice qui dispose
d'un PPN. Les localisations de la notice dans les établissements Sudoc sont
affichées sont affichées dans l'onglet _AbesWS_. Chaque établissement est un
lien vers la page Sudoc du RCR : nom de établissement, adresse, téléphone, etc.

**QualiMarc** — En activant l'option [QualiMarc](https://qualimarc.sudoc.fr),
l'API de l'outil d'analyse de l'Abes est appelé avec le PPN de la notice
courante. Le résultat de cette analyse est placé dans l'onglet _AbesWS_.

### IdRef OPAC Détail

En activant l'affichage IdRef à l'OPAC, la page de détail de l'OPAC est
enrichie d'informations récupérées via plusieurs services web de l'Abes en lien
avec IdRef.  Ces informations sont mises en cache sur le serveur Koha afin
d'éviter de saturer de requêtes le serveur de l'Abes. La durée de la mise en
cache est paramétrable (1 journée par défaut).

le service web
[biblio](https://documentation.abes.fr/aideidrefdeveloppeur/index.html#MicroWebBiblio)
de l'Abes.

La feuille de style de la page de détail doit insérer une balise
contenant les PPN des auteurs/collectivités. Le plugin utilisera ces PPN pour
aller chercher à la demande des informations IdRef. Les PPN doivent être dans
des balises de cette forme :

```html
<span class="idref-link" ppn="124680866"/>
```

Ce qu'on peut obtenir en insérant le code suivant à sa feuille de style XSL
dans les templates des zones 7xx :

```xml
<xsl:if test="marc:subfield[@code=3]">
  <span class="idref-link">
    <xsl:attribute name="ppn">
      <xsl:value-of select="str:encode-uri(marc:subfield[@code=3], true())"/>
    </xsl:attribute>
  </span>
</xsl:if>
```

Trois catégories d'informations sont affichables :

- **Infos complémentaires sur l'auteur** — On peut activer la récupération
  d'informations supplémentaires sur l'auteur/collectivité. Ce sont les formes
  du nom alternatives ou traduites, des notices sur l'auteurs.

- **Identifiants externes** — L'Abes procède régulièrement à des opérations
  d'alignement des identifiants IdRef (PPN) avec d'autres référentiels. Le
  résultat de ces alignements est rendu disponible via le service web
  [idref2id](https://documentation.abes.fr/aideidrefdeveloppeur/index.html#MicroWebIdref2id).
  Le plugin peut afficher à l'OPAC tout ou partie de ces identifiants externes.

- **Publications** — Les publications de l'auteur/collectivité sont
  retrouvées au moyen du service web
  [biblio](https://documentation.abes.fr/aideidrefdeveloppeur/index.html#MicroWebBiblio).
  Les publications sont affichées regroupées par fonction de l'auteur
  relativement à la publication. Chaque publication présente un lien pour
  afficher la notice dans le Sudoc, ainsi qu'un lien vers la notice locale si
  elle existe dans le Catalogue Koha.  L'identification des notices Koha se
  fait sur un index Elasticsearch **ppn**.

**Service web** — Le plugin utilise et expose un service web qui peut se
comprendre comme une extension des services de l'Abes liés à IdRef.  Pour
chaque auteur identifié par son PPN, il retourne les trois catégories
d'informations décrites ci-dessus.

Point d'entrée du service web du plugin pour, par exemple, le PPN
259238678 :

```
/api/v1/contrib/abesws/idref/259238678
```

qui renvoie :

```json
{
  "ppn": "027715078",
  "name": "Bourdieu, Pierre, 1930-2002",
  "altnames": null,
  "notes": [
    "Sociologue. - Professeur titulaire de la chaire Sociologie, au Collège de France, 1982-2001. - Directeur du Centre de Sociologie Européenne (CSE) du Collège de France et de l'Ecole des Hautes Etudes en Sciences Sociales, 1985-1998. - Directeur de la Collection \"Liber\" (Editions du Seuil), 1998-2002",
    "Titulaire de la chaire de Sociologie au Collège de France (1981-2001)",
    "Fondateur en 1975 de la revue \"Actes de la recherche en sciences sociales\""
  ],
  "altid": {
    "BNF": "http://catalogue.bnf.fr/ark:/12148/cb118934022",
    "ISNI": "0000000121385892",
    "VIAF": "http://viaf.org/viaf/71387829",
    "WIKIDATA": "Q156268",
    "WIKIPEDIA": "https://fr.wikipedia.org/wiki/Pierre_Bourdieu"
  },
  "roles": [
    {
      "code": "070",
      "docs": [
        {
          "ppn": "078457548",
          "biblionumber": 101,
          "citation": "\"Si le monde social m'est supportable, c'est parce que je peux m'indigner\"  / Pierre Bourdieu  ; entretien mené par Antoine Spire  ; assisté de Pascale Casanova et de Miguel Benassayag (1989-1990)  ; préface d'Antoine Spire / La Tour-d'Aigues : Éditions de l'Aube , DL 2004"
        },
        {
          "citation": "100 penseurs de la société  / Julien Damon / Paris : PUF , DL 2016",
          "ppn": "195570731"
        },
```

## VERSIONS

* **1.0.6** / février 2024 — Ajout infos provenant du webservice idref2id
* **1.0.5** / novembre 2023 — Fonctionnalité pour corriger les PPN IdRef
* **1.0.3** / octobre 2023 - Version initiale

## LICENCE

This software is copyright (c) 2024 by Tamil s.a.r.l.

This is free software; you can redistribute it and/or modify it under the same
terms as the Perl 5 programming language system itself.

