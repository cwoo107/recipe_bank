module BillingsHelper
  # "$5", "$4.33", "$52" — no ".00" on whole dollars.
  def plan_price(cents)
    number_to_currency(cents / 100.0, precision: (cents % 100).zero? ? 0 : 2)
  end
end
