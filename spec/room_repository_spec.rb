require_relative '../lib/hipmost/room_repository'

RSpec.describe Hipmost::RoomRepository do
  it "loads room data" do
    repo = described_class.new(".")
    repo.load(data)

    expect(repo.size).to eq(2)

    room = repo[206455]
    expect(room).to be_a(Hipmost::RoomRepository::Room)

    room_by_name = repo.find_by_name(room.name)
    expect(room_by_name).to eq(room)
  end

  let(:data) do
    <<-JSON
      [
        {
          "Room": {
            "created": "2013-05-27T13:29:02+00:00",
            "guest_access_url": null,
            "id": 206455,
            "is_archived": false,
            "members": [
              752160,
              1002528,
              844771,
              340070,
              1017103,
              340825
            ],
            "name": "Orbital Impact",
            "owner": 340070,
            "participants": [],
            "privacy": "private",
            "topic": "Welcome! Send this link to coworkers who need accounts: https://www.hipchat.com/invite/50371/3c380f069e21ba92e3441c57952e4ed0"
          }
        },
        {
          "Room": {
            "created": "2013-05-28T14:12:28+00:00",
            "guest_access_url": null,
            "id": 206977,
            "is_archived": false,
            "members": [],
            "name": "CFXWare",
            "owner": 340070,
            "participants": [],
            "privacy": "public",
            "topic": "CFXWare"
          }
        }
      ]
    JSON
  end
end
