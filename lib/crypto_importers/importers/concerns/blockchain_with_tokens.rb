module BlockchainWithTokens
  extend ActiveSupport::Concern
  included do
    # use this for coins that allow multiple tokens like ethereum, eos etc
    def fetch_token(name, symbol, token_address, create = false)
      name = name.present? ? name.strip : nil
      symbol = symbol.present? ? symbol.strip.upcase : nil
      token_address = token_address.present? ? token_address.strip.downcase : nil
      return if token_address.nil?

      @contracts ||= {}
      @contracts[token_address] ||= begin
        curr =
          Currency.unscoped.find_by(token_address: token_address) ||
          adapter.fetch_currency(SymbolAlias::TOKEN_ADDRESS_TAG, symbol: token_address) ||
          (symbol && adapter.resolve_symbol_alias(self.class.tag, symbol))

        if curr.nil? && name.present? && symbol.present?
          curr = adapter.fetch_currency(self.class.tag, symbol: symbol, name: name)
          curr = nil if curr && curr.added_by_user && currency && curr.platform_id && curr.platform_id != currency.id
          if curr && create
            Rollbar.debug(
              "matched #{currency.symbol} token to existing currency",
              token_address: token_address,
              existing_currency: [curr.id, curr.name, curr.symbol, curr.token_address].compact.join(', '),
              wallet_id: current_wallet.id,
            )
          end
        end

        if curr.nil? && create && symbol.present? && token_address.present?
          curr = currency.tokens.create!(
            name: name || symbol,
            symbol: symbol,
            token_address: token_address,
            added_by_user: true,
          )
        end

        curr
      end
    end
  end
end
