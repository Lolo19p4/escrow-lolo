# Escrow (dépôt sécurisé) – Station technique

## Comment ça marche
1. **L'acheteur crée un deal** : il indique l'adresse du vendeur et dépose l'argent (ETH ou USDC sur Base) dans le contrat. L'argent est bloqué.
2. **L'acheteur confirme** qu'il a reçu → le vendeur reçoit le montant **moins 2 %**. Ces 2 % partent vers ton adresse `0x30Ed…D036`.
3. **Problème ?** L'acheteur ou le vendeur ouvre un **litige**. Toi (le propriétaire/arbitre), tu décides : rembourser l'acheteur, ou payer le vendeur (avec frais).
4. **Délai (optionnel)** : si l'acheteur ne répond pas après la date limite (et sans litige), le vendeur peut récupérer son paiement.
5. Le vendeur peut aussi rembourser l'acheteur lui-même.

- Frais par défaut : 2 %. Tu peux les changer (`setFee`, en "points" : 200 = 2 %), **maximum 5 %**. Un deal garde les frais du moment où il a été créé.
- Pas de frais en cas de remboursement.
- Tokens acceptés au départ : ETH et USDC Base (`0x8335…2913`). Tu peux en ajouter avec `setAllowedToken`.
- Propriétaire et receveur des frais : `0x30Ed1738Dc49BC50b814a3a274e5571F9960D036` (écrit dans le contrat, rien à saisir).

## Déployer sur Base (réseau principal) avec Remix + Phantom
Il faut un peu d'ETH sur Base dans ton Phantom (quelques centimes suffisent en général).
**Important : le contrat te donne le contrôle à l'adresse `0x30Ed…D036`. Déploie avec Phantom EVM connecté sur cette adresse, sinon tu ne pourras pas gérer les litiges.**

1. Sur ton ordinateur (Chrome + extension Phantom), ouvre **https://remix.ethereum.org**.
2. Dans l'onglet fichiers, crée `EscrowFlat.sol` et colle tout le contenu du fichier `EscrowFlat.sol`.
3. Onglet **Solidity Compiler** : version **0.8.24 ou plus récente** (ex. 0.8.28), clique **Compile EscrowFlat.sol**.
4. Onglet **Deploy & Run** : Environment → **Injected Provider** (Phantom). Accepte la connexion. Dans Phantom, choisis le réseau **Base**. Remix doit afficher "Custom (8453)".
5. Contract → choisis **Escrow** (pas les autres), puis clique **Deploy**. Aucun paramètre à remplir.
6. Phantom affiche le frais → vérifie que c'est petit, puis **Confirmer**.
7. Copie l'adresse du contrat (en bas, "Deployed Contracts") et garde-la. Vérifie-la sur **basescan.org**.

## Utilisation (dans Remix, section "Deployed Contracts")
- **Deal en ETH** : `createDealETH(vendeur, deadline)` avec le montant dans "Value". Deadline = 0 si pas de délai (sinon une date en secondes Unix).
- **Deal en USDC** : d'abord `approve(adresseEscrow, montant)` sur le contrat USDC, puis `createDealToken(USDC, vendeur, montant, deadline)`. USDC a 6 décimales : 10 USDC = `10000000`.
- `confirm(id)` – l'acheteur paie le vendeur.
- `openDispute(id)` – ouvrir un litige.
- `resolveDispute(id, true/false)` – toi seul : true = payer le vendeur, false = rembourser l'acheteur.

## Sécurité
- Testé avec 18 tests (paiement, frais, remboursement, litiges, délai, pirates qui essaient de retirer deux fois, accès non autorisé).
- Code basé sur OpenZeppelin (standard du secteur). Pas d'audit professionnel : commence avec de petits montants.
- Ne donne jamais ta phrase secrète, ni à Remix ni à personne.
