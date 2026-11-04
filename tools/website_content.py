"""Texts of the Schiesstagebuch website, built by tools/website.py.

The privacy policy must match what the app does. Update it in the same PR when
the app starts sending data anywhere new (today: iCloud sync through Apple,
Apple Maps place search and map tiles, nothing to the developer).
"""

NAME = "Schiesstagebuch"
DOMAIN = "schiesstagebuch.apps.giotta.ch"
REPO_URL = "https://github.com/ravench/schiesstagebuch"
ICON = "Schiesstagebuch/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
# Set to the App Store page once the app is live; until then the site says "coming soon".
STORE_URL = ""
YEAR = 2026
UPDATED = {"de": "4. November 2026", "en": "4 November 2026", "fr": "4 novembre 2026", "it": "4 novembre 2026"}

CONTACT = {
    "email": "",
    "address": [],
    "uid": "CHE-177.370.768",
}

APP = {
    "de": {
        "tagline": "Das Schiesstagebuch für Schweizer Sportschützen, für iPhone und iPad.",
        "intro": "Halte jedes Training und jeden Anlass fest: Waffe, Munition, Schiessanlage, Schüsse und Resultat. "
                 "Die Statistik zeigt, wie viel du schiesst und wie sich deine Resultate entwickeln.",
        "features": [
            ("Tagebuch", [
                "Einträge mit Datum, Schiessanlage, Anlass, Waffe, Lauf, Kaliber, Munition und Los, Schüssen, Resultat, Notizen und Fotos.",
                "Anlässe mit mehreren Stichen, auch mit verschiedenen Waffen.",
                "Resultat als Total, mit Probe- und Wertungsschüssen oder Schuss für Schuss pro Passe.",
                "Standblätter scannen: Schüsse und Total werden gelesen und geprüft.",
            ]),
            ("Waffen und Munition", [
                "Waffen mit Läufen, Kalibern, Nummern, Kauf- und Verkaufsdatum.",
                "Pflege und Erinnerungen nach Schüssen oder Tagen.",
                "Munition mit Losnummern und Vergleich der Lose nach Resultat.",
                "Alle Schweizer Schiessanlagen auf Wunsch schon beim ersten Start.",
            ]),
            ("Für Sportschützen", [
                "Farbfilter, Diopter, Ring und Iris, Zweibeinstütze, Wetter mit Ablösungen.",
                "Jede Funktion einzeln einschaltbar; auf Wunsch «Sportgeräte» statt «Waffen».",
                "Import aus Schusszähler-Schiesstagebuch, Backup und CSV-Export.",
            ]),
        ],
        "note": "Deutsch, Englisch, Französisch und Italienisch. Ohne Konto, Tracking oder Werbung. "
                "Schiesstagebuch verkauft oder bewirbt weder Waffen noch Munition.",
        "privacy": {
            "summary": "Schiesstagebuch sendet mir keine Daten. Dein Tagebuch liegt auf deinem Gerät und, wenn du iCloud nutzt, in deinem eigenen iCloud.",
            "sections": [
                ("Dein Tagebuch und iCloud", [
                    "Einträge, Waffen, Munition, Schiessanlagen, Fotos, Lizenzangaben und Einstellungen werden auf "
                    "dem Gerät gespeichert. Bist du bei iCloud angemeldet, gleicht die App sie über deine private "
                    "iCloud-Datenbank zwischen deinen Geräten ab. Diese Daten verarbeitet Apple nach seiner "
                    "Datenschutzerklärung; ich habe keinen Zugriff darauf.",
                    "Backups und CSV-Exporte sind Dateien, die du selbst speicherst oder teilst.",
                ]),
                ("Standort und Karten", [
                    "Beim neuen Eintrag kann die App deinen Standort verwenden, um die nächste Schiessanlage "
                    "vorzuschlagen. Der Standort wird nur dafür genutzt und nicht gespeichert.",
                    "Suchst du einen Ort für eine Schiessanlage, geht der Suchtext an Apple Karten. Karten werden von "
                    "Apple geladen. Die Liste der Schweizer Schiessanlagen ist in der App enthalten.",
                ]),
                ("Kamera, Fotos und Mitteilungen", [
                    "Die Kamera dient zum Fotografieren von Standblättern; der Text wird auf dem Gerät gelesen. "
                    "Fotos, die du einem Eintrag hinzufügst, werden mit dem Tagebuch gespeichert.",
                    "Zugriff auf die Mediathek braucht die App nur beim Import aus Schusszähler-Schiesstagebuch, "
                    "um die Bilder der Einträge zu übernehmen.",
                    "Pflege-Erinnerungen sind Mitteilungen, die auf dem Gerät geplant werden.",
                ]),
                ("Keine Analyse, keine Werbung", [
                    "Die App enthält keine Statistik-, Absturz- oder Werbedienste und keine Software von Dritten, "
                    "die Daten sendet. Es gibt kein Konto.",
                ]),
            ],
        },
        "support_intro": "Antworten auf häufige Fragen. Hilft das nicht weiter, schreib mir.",
        "faq": [
            ("Wie sichere ich meine Daten?",
             "Mit iCloud sind sie auf allen deinen Geräten. Zusätzlich kannst du unter Einstellungen «Backup "
             "exportieren» wählen und die Datei an einem sicheren Ort ablegen; «Backup wiederherstellen» liest sie wieder ein."),
            ("Wie übernehme ich meine Einträge aus Schusszähler-Schiesstagebuch?",
             "Exportiere dort deine Daten und wähle in den Einstellungen den Import aus «Schusszähler-Schiesstagebuch»."),
            ("Ein Standblatt wird nicht richtig gelesen.",
             "Fotografiere es gerade, flach und gut beleuchtet. Die App prüft die gelesenen Schüsse gegen die "
             "gedruckten Summen; Abweichungen zeigt sie an, und du kannst jeden Wert von Hand korrigieren."),
            ("Fehlt eine Schiessanlage?",
             "Du kannst sie selbst erfassen. Schreib mir trotzdem, dann nehme ich sie in die Liste auf."),
        ],
    },
    "en": {
        "tagline": "The shooting log for Swiss sport shooters, for iPhone and iPad.",
        "intro": "Record every practice and every event: firearm, ammunition, shooting range, shots and result. "
                 "The statistics show how much you shoot and how your results develop.",
        "features": [
            ("Log", [
                "Entries with date, shooting range, event, firearm, barrel, calibre, ammunition and lot, shots, result, notes and photos.",
                "Events with several matches (Stiche), even with different firearms.",
                "Results as a total, with sighters and scored shots, or shot by shot per Passe.",
                "Scan score strips (Standblätter): shots and total are read and checked.",
            ]),
            ("Firearms and ammunition", [
                "Firearms with barrels, calibres, serial numbers, purchase and sale dates.",
                "Maintenance log and reminders after a number of shots or days.",
                "Ammunition with lot numbers, and lots compared by result.",
                "All Swiss shooting ranges, offered on first launch.",
            ]),
            ("For sport shooters", [
                "Colour filters, diopter, ring and iris, bipod, weather with relays.",
                "Each feature switched on by itself; optionally «Sportgeräte» instead of «Waffen».",
                "Import from Schusszähler-Schiesstagebuch, backup and CSV export.",
            ]),
        ],
        "note": "English, German, French and Italian. No account, tracking or ads. "
                "Schiesstagebuch does not sell or advertise firearms or ammunition.",
        "privacy": {
            "summary": "Schiesstagebuch sends no data to me. Your log stays on your device and, if you use iCloud, in your own iCloud.",
            "sections": [
                ("Your log and iCloud", [
                    "Entries, firearms, ammunition, shooting ranges, photos, licence details and settings are stored "
                    "on the device. If you are signed in to iCloud, the app syncs them between your devices through "
                    "your private iCloud database. Apple processes this data under its privacy policy; I have no "
                    "access to it.",
                    "Backups and CSV exports are files that you save or share yourself.",
                ]),
                ("Location and maps", [
                    "When you add an entry, the app can use your location to suggest the nearest shooting range. "
                    "The location is used only for that and is not stored.",
                    "When you search for a place for a shooting range, the search text goes to Apple Maps. Maps are "
                    "loaded from Apple. The list of Swiss shooting ranges is built into the app.",
                ]),
                ("Camera, photos and notifications", [
                    "The camera is used to photograph score strips; the text is read on the device. Photos you add "
                    "to an entry are stored with the log.",
                    "The app needs photo library access only when importing from Schusszähler-Schiesstagebuch, to "
                    "bring over the pictures of the entries.",
                    "Maintenance reminders are notifications scheduled on the device.",
                ]),
                ("No analytics, no ads", [
                    "The app contains no analytics, crash reporting or advertising services and no third-party "
                    "software that sends data. There is no account.",
                ]),
            ],
        },
        "support_intro": "Answers to common questions. If they don't help, write to me.",
        "faq": [
            ("How do I back up my data?",
             "With iCloud it is on all your devices. You can also choose «Export backup» in Settings and keep the "
             "file somewhere safe; «Restore backup» reads it back."),
            ("How do I bring over my entries from Schusszähler-Schiesstagebuch?",
             "Export your data there, then choose the import from «Schusszähler-Schiesstagebuch» in Settings."),
            ("A score strip is not read correctly.",
             "Photograph it straight, flat and well lit. The app checks the shots it read against the printed "
             "sums, shows any difference, and you can correct every value by hand."),
            ("Is a shooting range missing?",
             "You can add it yourself. Please still write to me, and I'll add it to the list."),
        ],
    },
    "fr": {
        "tagline": "Le journal de tir des tireurs sportifs suisses, pour iPhone et iPad.",
        "intro": "Notez chaque entraînement et chaque manifestation : arme, munition, stand de tir, coups et résultat. "
                 "Les statistiques montrent combien vous tirez et comment vos résultats évoluent.",
        "features": [
            ("Journal", [
                "Entrées avec date, stand de tir, manifestation, arme, canon, calibre, munition et lot, coups, résultat, notes et photos.",
                "Manifestations avec plusieurs passes (Stiche), même avec des armes différentes.",
                "Résultat en total, avec coups d'essai et coups comptés, ou coup par coup par passe.",
                "Scanner les feuilles de stand : les coups et le total sont lus et vérifiés.",
            ]),
            ("Armes et munitions", [
                "Armes avec canons, calibres, numéros, dates d'achat et de vente.",
                "Entretien et rappels après un nombre de coups ou de jours.",
                "Munitions avec numéros de lot, et lots comparés selon le résultat.",
                "Tous les stands de tir suisses, proposés au premier lancement.",
            ]),
            ("Pour les tireurs sportifs", [
                "Filtres de couleur, dioptre, anneau et iris, bipied, météo avec relèves.",
                "Chaque fonction s'active séparément ; au choix « Sportgeräte » au lieu de « Waffen ».",
                "Import depuis Schusszähler-Schiesstagebuch, sauvegarde et export CSV.",
            ]),
        ],
        "note": "Français, allemand, anglais et italien. Sans compte, suivi ni publicité. "
                "Schiesstagebuch ne vend ni ne promeut d'armes ou de munitions.",
        "privacy": {
            "summary": "Schiesstagebuch ne m'envoie aucune donnée. Votre journal reste sur votre appareil et, si vous utilisez iCloud, dans votre propre iCloud.",
            "sections": [
                ("Votre journal et iCloud", [
                    "Les entrées, armes, munitions, stands de tir, photos, données de licence et réglages sont "
                    "enregistrés sur l'appareil. Si vous êtes connecté à iCloud, l'app les synchronise entre vos "
                    "appareils via votre base de données iCloud privée. Apple traite ces données selon sa politique "
                    "de confidentialité ; je n'y ai pas accès.",
                    "Les sauvegardes et exports CSV sont des fichiers que vous enregistrez ou partagez vous-même.",
                ]),
                ("Position et cartes", [
                    "Lors d'une nouvelle entrée, l'app peut utiliser votre position pour proposer le stand de tir le "
                    "plus proche. La position sert uniquement à cela et n'est pas enregistrée.",
                    "Si vous cherchez un lieu pour un stand de tir, le texte recherché est envoyé à Apple Plans. Les "
                    "cartes sont chargées depuis Apple. La liste des stands de tir suisses est intégrée à l'app.",
                ]),
                ("Appareil photo, photos et notifications", [
                    "L'appareil photo sert à photographier les feuilles de stand ; le texte est lu sur l'appareil. "
                    "Les photos ajoutées à une entrée sont enregistrées avec le journal.",
                    "L'app n'a besoin d'accéder à la photothèque que pour l'import depuis Schusszähler-Schiesstagebuch, "
                    "afin de reprendre les images des entrées.",
                    "Les rappels d'entretien sont des notifications planifiées sur l'appareil.",
                ]),
                ("Ni statistiques ni publicité", [
                    "L'app ne contient aucun service de statistiques, de rapport de plantage ou de publicité, ni "
                    "logiciel tiers qui envoie des données. Il n'y a pas de compte.",
                ]),
            ],
        },
        "support_intro": "Réponses aux questions fréquentes. Si elles ne suffisent pas, écrivez-moi.",
        "faq": [
            ("Comment sauvegarder mes données ?",
             "Avec iCloud, elles sont sur tous vos appareils. Vous pouvez aussi choisir « Exporter une sauvegarde » "
             "dans les réglages et garder le fichier en lieu sûr ; « Restaurer une sauvegarde » le relit."),
            ("Comment reprendre mes entrées de Schusszähler-Schiesstagebuch ?",
             "Exportez-y vos données, puis choisissez l'import depuis « Schusszähler-Schiesstagebuch » dans les réglages."),
            ("Une feuille de stand est mal lue.",
             "Photographiez-la bien droite, à plat et bien éclairée. L'app compare les coups lus aux sommes "
             "imprimées, signale les écarts, et vous pouvez corriger chaque valeur à la main."),
            ("Un stand de tir manque ?",
             "Vous pouvez l'ajouter vous-même. Écrivez-moi quand même, je l'ajouterai à la liste."),
        ],
    },
    "it": {
        "tagline": "Il diario di tiro per i tiratori sportivi svizzeri, per iPhone e iPad.",
        "intro": "Registra ogni allenamento e ogni manifestazione: arma, munizioni, poligono, colpi e risultato. "
                 "Le statistiche mostrano quanto spari e come evolvono i tuoi risultati.",
        "features": [
            ("Diario", [
                "Voci con data, poligono, manifestazione, arma, canna, calibro, munizioni e lotto, colpi, risultato, note e foto.",
                "Manifestazioni con più serie (Stiche), anche con armi diverse.",
                "Risultato come totale, con colpi di prova e colpi validi, o colpo per colpo per passe.",
                "Scansione dei fogli di tiro: colpi e totale vengono letti e controllati.",
            ]),
            ("Armi e munizioni", [
                "Armi con canne, calibri, numeri di serie, date di acquisto e di vendita.",
                "Manutenzione e promemoria dopo un numero di colpi o di giorni.",
                "Munizioni con numeri di lotto, e lotti confrontati per risultato.",
                "Tutti i poligoni svizzeri, proposti al primo avvio.",
            ]),
            ("Per tiratori sportivi", [
                "Filtri colorati, diottra, anello e iride, bipiede, meteo con turni.",
                "Ogni funzione si attiva da sola; a scelta «Sportgeräte» invece di «Waffen».",
                "Importazione da Schusszähler-Schiesstagebuch, backup ed esportazione CSV.",
            ]),
        ],
        "note": "Italiano, tedesco, francese e inglese. Senza account, tracciamento o pubblicità. "
                "Schiesstagebuch non vende né promuove armi o munizioni.",
        "privacy": {
            "summary": "Schiesstagebuch non mi invia dati. Il tuo diario resta sul tuo dispositivo e, se usi iCloud, nel tuo iCloud.",
            "sections": [
                ("Il tuo diario e iCloud", [
                    "Voci, armi, munizioni, poligoni, foto, dati della licenza e impostazioni vengono salvati sul "
                    "dispositivo. Se hai effettuato l'accesso a iCloud, l'app li sincronizza tra i tuoi dispositivi "
                    "tramite il tuo database iCloud privato. Apple tratta questi dati secondo la sua informativa "
                    "sulla privacy; io non vi ho accesso.",
                    "Backup ed esportazioni CSV sono file che salvi o condividi tu stesso.",
                ]),
                ("Posizione e mappe", [
                    "Quando aggiungi una voce, l'app può usare la tua posizione per proporre il poligono più vicino. "
                    "La posizione serve solo a questo e non viene salvata.",
                    "Se cerchi un luogo per un poligono, il testo cercato va a Mappe di Apple. Le mappe vengono "
                    "caricate da Apple. L'elenco dei poligoni svizzeri è incluso nell'app.",
                ]),
                ("Fotocamera, foto e notifiche", [
                    "La fotocamera serve a fotografare i fogli di tiro; il testo viene letto sul dispositivo. Le foto "
                    "aggiunte a una voce vengono salvate con il diario.",
                    "L'app accede alla libreria foto solo durante l'importazione da Schusszähler-Schiesstagebuch, per "
                    "riprendere le immagini delle voci.",
                    "I promemoria di manutenzione sono notifiche pianificate sul dispositivo.",
                ]),
                ("Niente statistiche, niente pubblicità", [
                    "L'app non contiene servizi di statistica, di segnalazione degli arresti o di pubblicità, né "
                    "software di terzi che invia dati. Non c'è nessun account.",
                ]),
            ],
        },
        "support_intro": "Risposte alle domande frequenti. Se non bastano, scrivimi.",
        "faq": [
            ("Come faccio il backup dei miei dati?",
             "Con iCloud sono su tutti i tuoi dispositivi. Puoi anche scegliere «Esporta backup» nelle impostazioni e "
             "conservare il file in un luogo sicuro; «Ripristina backup» lo rilegge."),
            ("Come riprendo le mie voci da Schusszähler-Schiesstagebuch?",
             "Esporta lì i tuoi dati, poi scegli l'importazione da «Schusszähler-Schiesstagebuch» nelle impostazioni."),
            ("Un foglio di tiro non viene letto bene.",
             "Fotografalo dritto, in piano e ben illuminato. L'app confronta i colpi letti con le somme stampate, "
             "segnala le differenze e puoi correggere ogni valore a mano."),
            ("Manca un poligono?",
             "Puoi aggiungerlo tu. Scrivimi comunque, così lo aggiungo all'elenco."),
        ],
    },
}
