# Exemplars: Credible Causal Identification in IR/Political Science

Papers with credible causal identification strategies published in top journals, for inspiration.

---

## I. Most Relevant (China / Trade / UNGA / Foreign Policy)

### 1. Flores-Macias & Kreps (2013)
Flores-Macias, Gustavo A., and Sarah E. Kreps. 2013. "The Foreign Policy Consequences of Trade: China's Commercial Relations with Africa and Latin America, 1992-2006." *The Journal of Politics* 75(2): 357-371. DOI: 10.1017/S0022381613000066

- **Method**: 2SLS / Instrumental Variables
- **Question**: Does trade with China cause UNGA voting convergence?
- **Why look**: The closest paper to yours — same outcome (UNGA), same treatment country (China). You already critique their identification (lagged energy production instrument fails exclusion restriction). Your SDiD is a direct improvement.

### 2. Fuchs & Klann (2013)
Fuchs, Andreas, and Nils-Hendrik Klann. 2013. "Paying a Visit: The Dalai Lama Effect on International Trade." *Journal of International Economics* 91(1): 164-177. DOI: 10.1016/j.jinteco.2013.04.007

- **Method**: Instrumental Variables
- **Question**: Does receiving the Dalai Lama reduce exports to China?
- **Why look**: China punishes via trade. Clean instruments (Tibet Support Groups + travel schedule). Effect vanishes after 2 years — parallel to your attenuation finding.

### 3. Malis (2021)
Malis, Matt. 2021. "Conflict, Cooperation, and Delegated Diplomacy." *International Organization* 75(4): 1018-1057. DOI: 10.1017/S0020818321000102

- **Method**: Natural experiment (ambassadorial rotation)
- **Question**: Does diplomatic representation affect conflict and trade?
- **Why look**: Published in IO (your target journal). Uses quasi-experimental variation in diplomacy. Model for how to connect mechanism to estimand in an IR paper.

### 4. Davis, Fuchs & Johnson (2019)
Davis, Christina L., Andreas Fuchs, and Kristina Johnson. 2019. "State Control and the Effects of Foreign Relations on Bilateral Trade." *Journal of Conflict Resolution* 63(2): 405-438. DOI: 10.1177/0022002717739087

- **Method**: Panel FE / DiD-style
- **Question**: Can governments use trade to reward/punish partner countries?
- **Why look**: Disaggregates SOE vs. private imports — built-in placebo test. Shows mechanism for how political relations affect trade with China.

### 5. Dreher, Fuchs, Parks, Strange & Tierney (2018)
Dreher, Axel, Andreas Fuchs, Bradley Parks, Austin M. Strange, and Michael J. Tierney. 2018. "Apples and Dragon Fruits: The Determinants of Aid and Other Forms of State Financing from China to Africa." *International Studies Quarterly* 62(1): 182-194. DOI: 10.1093/isq/sqx052

- **Method**: Panel analysis with new disaggregated data
- **Question**: What drives China's aid allocation to Africa?
- **Why look**: Published in ISQ (another target). Shows China allocates aid based on UNGA voting alignment. The AidData dataset is a major contribution in itself.

### 6. Berger, Easterly, Nunn & Satyanath (2013)
Berger, Daniel, William Easterly, Nathan Nunn, and Shanker Satyanath. 2013. "Commercial Imperialism? Political Influence and Trade during the Cold War." *American Economic Review* 103(2): 863-896. DOI: 10.1257/aer.103.2.863

- **Method**: IV / Historical natural experiment
- **Question**: Did CIA interventions create markets for US products?
- **Why look**: Shows political influence causally shapes trade. Imports surge in sectors where US has comparative *disadvantage* — brilliant mechanism test.

---

## II. Methodological Exemplars (Natural Experiments in IR)

### 7. Carnegie & Marinov (2017)
Carnegie, Allison, and Nikolay Marinov. 2017. "Foreign Aid, Human Rights, and Democracy Promotion: Evidence from a Natural Experiment." *American Journal of Political Science* 61(3): 671-683. DOI: 10.1111/ajps.12289

- **Method**: IV exploiting EU Council rotation
- **Why look**: Rotation of EU Council presidency is institutionally determined and quasi-random. Model for how institutional rotation = natural experiment.

### 8. Kuziemko & Werker (2006)
Kuziemko, Ilyana, and Eric Werker. 2006. "How Much Is a Seat on the Security Council Worth? Foreign Aid and Bribery at the United Nations." *Journal of Political Economy* 114(5): 905-930. DOI: 10.1086/507155

- **Method**: Natural experiment (UNSC rotation)
- **Why look**: US aid increases 59% during UNSC membership. Sharp entry/exit timing provides clean identification. Foundational for vote-buying in international institutions.

### 9. Dreher, Sturm & Vreeland (2009)
Dreher, Axel, Jan-Egbert Sturm, and James Raymond Vreeland. 2009. "Development Aid and International Politics: Does Membership on the UN Security Council Influence World Bank Decisions?" *Journal of Development Economics* 88(1): 1-18. DOI: 10.1016/j.jdeveco.2008.02.003

- **Method**: Natural experiment (UNSC rotation)
- **Why look**: Extends Kuziemko & Werker to World Bank lending. Same design, different outcome — shows generalizability.

### 10. Fisman & Miguel (2007)
Fisman, Raymond, and Edward Miguel. 2007. "Corruption, Norms, and Legal Enforcement: Evidence from Diplomatic Parking Tickets." *Journal of Political Economy* 115(6): 1020-1048. DOI: 10.1086/527495

- **Method**: Natural experiment (diplomatic immunity)
- **Why look**: One of the most elegant natural experiments in social science. Diplomatic immunity holds enforcement constant, isolating cultural norms. Model for clean design.

---

## III. DiD Exemplars

### 11. Dube, Dube & Garcia-Ponce (2013)
Dube, Arindrajit, Oeindrila Dube, and Omar Garcia-Ponce. 2013. "Cross-Border Spillover: U.S. Gun Laws and Violence in Mexico." *American Political Science Review* 107(3): 397-417. DOI: 10.1017/S0003055413000178

- **Method**: Difference-in-Differences
- **Why look**: Published in APSR. California state ban provides clean control group for Mexican municipalities. Model for cross-border policy spillover DiD.

### 12. Autor, Dorn & Hanson (2013)
Autor, David H., David Dorn, and Gordon H. Hanson. 2013. "The China Syndrome: Local Labor Market Effects of Import Competition in the United States." *American Economic Review* 103(6): 2121-2168. DOI: 10.1257/aer.103.6.2121

- **Method**: Shift-share / Bartik instrument in DiD framework
- **Why look**: THE China trade shock paper. Methodological benchmark for any study of China's trade impact. Third-country imports instrument removes US demand shocks.

### 13. Nunn & Qian (2014)
Nunn, Nathan, and Nancy Qian. 2014. "US Food Aid and Civil Conflict." *American Economic Review* 104(6): 1630-1666. DOI: 10.1257/aer.104.6.1630

- **Method**: IV (shift-share)
- **Why look**: US wheat production x historical recipient status. Canonical shift-share design in aid-conflict nexus. Also illustrates pitfalls (methodological debate on interacted instruments).

---

## IV. Synthetic Control Exemplars

### 14. Abadie & Gardeazabal (2003)
Abadie, Alberto, and Javier Gardeazabal. 2003. "The Economic Costs of Conflict: A Case Study of the Basque Country." *American Economic Review* 93(1): 113-132. DOI: 10.1257/000282803321455188

- **Method**: Synthetic Control Method (founding paper)
- **Why look**: Invented the method you use (via SDiD extension). Weighted combination of Spanish regions as counterfactual. Ceasefire provides natural validation.

### 15. Borin, Conteduca & Mancini (2024)
Borin, Alessandro, Francesco Paolo Conteduca, and Michele Mancini. 2024. "The Real-Time Impact of the War on Russian Imports: A Synthetic Control Method Approach." *World Trade Review* 23(4): 433-447. DOI: 10.1017/S1474745623000484

- **Method**: Synthetic Control Method
- **Why look**: Most recent SCM application to trade/sanctions. Shows how to construct counterfactual trade trajectories from non-sanctioning countries.
