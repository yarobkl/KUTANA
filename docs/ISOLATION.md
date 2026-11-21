# KUTANA — isolation stricte

**Base réellement créée** : Supabase `kutana`, projet `xwhjzftrzikgqweowtus` en `eu-west-3`. Son URL et sa clé publique sont inscrites dans `project.yml`. Aucune clé de service ou secret n'est incorporé dans le client iOS.

**Dépôt GitHub à créer** : `yarobkl/KUTANA`, de visibilité `private`. Il n'existe pas encore dans les dépôts accessibles au connecteur GitHub à la date de cette version. Aucun dépôt COVI, BININGA ou Congo Emploi ne doit être utilisé ou modifié.

**Bundle ID réservé** : `fr.yaroconsulting.kutana`. Ne pas réutiliser un identifiant ou un certificat d'une autre application.

SwiftUI pour iOS et, plus tard, Jetpack Compose pour Android. Les deux clients KUTANA partageront **uniquement** la base KUTANA. Aucun transfert entre bases anciennes et nouvelles n'est prévu.

Ne jamais stocker les clés `service_role`, secrets SMTP, jetons APNs, `.p8`, `.p12` ni certificats dans Git ou dans les fichiers publiés. Garder les environnements de test et de production distincts avant lancement public.
