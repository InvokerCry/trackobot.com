require 'spec_helper'

describe ResultsController do
  let(:user) { FactoryGirl.create(:user) }

  before do
    sign_in(user)
  end

  describe 'POST create' do
    let(:result_params) do
      {
        hero: 'Shaman',
        opponent: 'Warrior',
        mode: 'ranked',
        coin: true,
        win: true,
        added: '2016-02-02T21:06:00Z'
      }
    end

    let(:card_history) do
      [
        {card_id: 'EX1_405', player: 'opponent'},
        {card_id: 'GAME_005', player: 'me', turn: 3}
      ]
    end

    it 'creates a result' do
      post :create, result: result_params, format: :json
      result = user.results.last

      expect(result.hero.name).to eq('Shaman')
      expect(result.opponent.name).to eq('Warrior')
      expect(result.mode).to eq 'ranked'
      expect(result.coin).to eq true
      expect(result.win).to eq true
      expect(result.added).to eq Time.parse('2016-02-02T21:06:00Z')
    end

    context 'with duration information' do
      it 'creates a result' do
        result_params.merge!(duration: 42)
        post :create, result: result_params, format: :json
        result = user.results.last
        expect(result.duration).to eq 42
      end
    end

    context 'with rank information' do
      let(:chicken) { 25 }

      it 'creates a result' do
        result_params.merge!(rank: chicken)
        post :create, result: result_params, format: :json
        result = user.results.last
        expect(result.rank).to eq chicken
      end
    end

    context 'with legend information' do
      it 'creates a result' do
        result_params.merge!(legend: 1337)
        post :create, result: result_params, format: :json
        result = user.results.last
        expect(result.legend).to eq 1337
      end
    end

    it 'adds history' do
      post :create, result: result_params.merge(card_history: card_history), format: :json
      result = user.results.last

      expect(result.card_history_list.count).to eq 2

      expect(result.card_history_list.first.card.name).to eq 'Shieldbearer'
      expect(result.card_history_list.first.player).to eq :opponent
      expect(result.card_history_list.first.turn).to eq 0 # make sure we can add card history elements without turn info

      expect(result.card_history_list.second.card.name).to eq 'The Coin'
      expect(result.card_history_list.second.player).to eq :me
      expect(result.card_history_list.second.turn).to eq 3
    end

    describe 'card playable status' do
      let(:card) { Card.find_by_ref(card_history.first[:card_id]) }

      before do
        card.update_attributes(playable: false)
      end

      it 'mark cards as playable when they are seen for the first time' do
        expect {
          post :create, result: result_params.merge(card_history: card_history), format: :json
        }.to change { card.reload.playable? }
      end
    end

    describe 'deck support' do
      let!(:miracle) { user.decks.create!(name: 'Miracle', hero: Hero.find_by_name('Rogue'), card_ids: Card.where(name: 'Gadgetzan Auctioneer').pluck(:id)) }
      let!(:handlock) { user.decks.create!(name: 'Handlock', hero: Hero.find_by_name('Warlock'), card_ids: Card.where(name: 'Mountain Giant').pluck(:id)) }

      let(:result_params) do
        {
          hero: 'Rogue',
          opponent: 'Warlock',
          mode: 'ranked',
          coin: true,
          win: true
        }
      end

      let(:card_history) do
        [
          {card_id: 'EX1_105', player: 'opponent'}, # opponent played handlock
          {card_id: 'EX1_095', player: 'me'} # I played miracle
        ]
      end

      context 'for non-arenas' do
        it 'assigns decks on upload' do
          post :create, result: result_params.merge(card_history: card_history), format: :json
          result = user.results.last

          expect(result.deck).to eq miracle
          expect(result.opponent_deck).to eq handlock
        end
      end

      context 'for arenas' do
        it 'does not assign decks on upload' do
          post :create, result: result_params.merge(mode: 'arena', card_history: card_history), format: :json
          result = user.results.last

          expect(result.deck).to be_nil
          expect(result.opponent_deck).to be_nil
        end
      end
    end

  end

  describe 'DELETE bulk_delete' do
    let(:result_user) { user }
    let!(:first_result) { FactoryGirl.create(:result, user: result_user) }
    let!(:second_result) { FactoryGirl.create(:result, user: result_user) }

    it 'destroys the requested results' do
      expect{
        delete :bulk_delete, { result_ids: [first_result.id, second_result.id] }
      }.to change(Result, :count).by(-2)
    end

    context 'as another user' do
      let(:result_user) { FactoryGirl.create(:user) }

      it 'gives you the finger' do
        expect {
          delete :bulk_delete, { result_ids: [first_result.id, second_result.id] }
        }.to_not change(Result, :count)
      end
    end
  end

  describe 'PUT bulk_update' do
    let(:result_user) { user }

    let(:shaman) { Hero.find_by_name('Shaman') }
    let(:warrior) { Hero.find_by_name('Warrior') }
    let(:priest) { Hero.find_by_name('Priest') }

    let(:shaman_deck) { FactoryGirl.create(:deck, hero: shaman, user: result_user) }
    let(:warrior_deck) { FactoryGirl.create(:deck, hero: warrior, user: result_user) }

    let!(:first_result) { FactoryGirl.create(:result, user: result_user, hero: shaman, opponent: warrior) }
    let!(:second_result) { FactoryGirl.create(:result, user: result_user, hero: shaman, opponent: priest) }

    it 'sets the selected results' do
      put :bulk_update, { result_ids: [first_result.id, second_result.id], as_deck: shaman_deck.id }
      expect(first_result.reload.deck).to eq shaman_deck
      expect(second_result.reload.deck).to eq shaman_deck
    end

    it 'respects the class' do
      put :bulk_update, { result_ids: [first_result.id, second_result.id], vs_deck: warrior_deck.id }
      expect(first_result.reload.opponent_deck).to eq warrior_deck
      expect(second_result.reload.opponent_deck).to_not eq warrior_deck
    end

    it 'ignores update for arenas' do
      first_result.update_attributes(mode: :arena)
      expect {
        put :bulk_update, { result_ids: [first_result.id, second_result.id], as_deck: shaman_deck.id }
      }.to_not change { first_result.reload.deck }
    end

    context 'as another user' do
      let(:result_user) { FactoryGirl.create(:user) }

      it 'can\'t touch this' do
        expect {
          put :bulk_update, { result_ids: [first_result.id, second_result.id], as_deck: shaman_deck.id }
        }.to_not change { first_result.reload.updated_at }
        expect(first_result.reload.deck).to_not eq shaman_deck
      end
    end
  end

  describe 'PUT set_tags' do
    let(:result) { FactoryGirl.create(:result, user: user) }

    let(:tags_array) { ['misplay', 'cool match'] }
    let(:tags) { tags_array.join ',' }

    it 'sets the tags' do
      expect {
        put :set_tags, id: result.id, tags: tags
      }.to change { result.reload.tags.collect(&:tag) }.to eq tags_array
    end

    context 'as another user' do
      let(:another_user) { FactoryGirl.create(:user) }
      let(:result) { FactoryGirl.create(:result, user: another_user) }

      it 'yields 404' do
        expect {
          put :set_tags, id: result.id, tags: tags
        }.to raise_error ActiveRecord::RecordNotFound
      end
    end
  end

end
