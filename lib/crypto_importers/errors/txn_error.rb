class TxnError < ArgumentError
  attr_accessor :errors, :txn

  def initialize(error)
    if error.is_a? String
      super(error)
    else
      self.txn = error if error.is_a? Txn
      self.errors = error.errors
      super(errors.full_messages.join(', '))
    end
  end
end
