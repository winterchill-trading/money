Convert at a decimal price and at its exact inverse:

  $ money convert "100.00 EUR" -to USD -price 1.0845
  108.45 USD
  $ money convert "108.45 USD" -to EUR -price 2000/2169
  100.00 EUR
  $ money convert "0.05 EUR" -to USD -price 1.0845 -rounding up
  0.06 USD
  $ money convert "1.5 ETH" -to USDC@polygon -price 2500.123456789
  3750.185185 USDC@polygon

Fees round down when payable and up when receivable:

  $ money fee "10.01 EUR" -fixed 0.25 -bps 150 -min 0.30 -side payable
  0.40 EUR
  $ money fee "10.01 EUR" -fixed 0.25 -bps 150 -min 0.30 -side receivable
  0.41 EUR
  $ money fee "5000.00 EUR" -bps 150 -max 25
  25.00 EUR

Bad input is rejected, never rounded away:

  $ money convert "1.234 EUR" -to USD -price 1 2>&1 | head -3
  Error parsing command line:
  
    failed to parse AMOUNT value "1.234 EUR"
  $ money convert "1.00 EUR" -to EUR -price 1
  ("rate: base and quote are the same" (base EUR))
  [1]
