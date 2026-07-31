# Quote verification

182 quotes checked. `partial` means the opening 60 characters matched but the full quote did not, usually an elision or a run-on across a column break.

| status | n |
|---|---:|
| ok | 180 |
| near | 2 |

## Quotes needing a look

`near` means the opening matched and the full string did not, which is usually an elision or a line break in the extracted text; check it and either fix the quote or leave it. `NOT-FOUND` means the text is not in the paper at all.

| batch | paper | attached to | status | quote |
|---|---|---|---|---|
| core-01 | L0006 | STR-01 | near | Interventions with a treatment duration (eg, medication), intermittent prescriptions, or specific preoperative preparation require more careful definition of th |
| core-02 | L0045 | LRN-01 | near | while allowing for flexible estimation of nuisance parameters, when grounded in a frequentist statistical model, the proposed BART estimators do not solve an ef |
