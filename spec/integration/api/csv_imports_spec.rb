RSpec.describe "Csv Imports", type: :request do
  context 'custom' do
    it_behaves_like 'csv import', 'sample.csv'
  end

  context "abra" do
    it_behaves_like 'csv import', 'abra_14TDVKS_Transaction_History_2018_(1).csv'
  end

  context "anxpro" do
    it_behaves_like 'csv import', 'anxpro-transaction_report.csv'
  end

  context "zelcore" do
    it_behaves_like 'csv import', 'XZC_transactions_Bawler-zelcore.csv'
  end

  context "coindeal" do
    it_behaves_like 'csv import', 'coindeal-My_transactions.csv'
  end

  context "polonidex" do
    # this file was created manually from the polonidex order history page
    it_behaves_like 'csv import', 'polonidex-copypaste.csv'
  end

  context "coinmetro-transactions" do
    it_behaves_like 'csv import', 'coin-metro-transactions.csv'
  end

  context "coinmetro-export" do
    it_behaves_like 'csv import', 'coinmetro-export.csv'
  end

  context "coinsmart" do
    it_behaves_like 'csv import', 'CoinSmart.csv'
  end

  context "coinsmart-transactions" do
    it_behaves_like 'csv import', 'coinsmart-Transactions (15).csv'
  end
end
