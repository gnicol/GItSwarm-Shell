module PerforceSwarm
  module P4
    module Spec
      class Depot
        # given a connection and either a single depot or an array of them, this method returns either a boolean
        # true/false for the existence of a single depot or a list of depots that exist if given more than one
        def self.exists?(id, connection)
          found = []
          ids   = [*id]
          connection.run('depots').each do |depot|
            next unless ids.include?(depot['name'])
            found.push(depot['name'])
          end
          # for single existence return whether we found one, otherwise return all (if any) found
          return id.is_a?(Array) ? found : !found.empty?
        rescue
          # command bombed for whatever reason, so return false/empty
          return id.is_a?(Array) ? [] : false
        end

        # Create the specified depot. If the depot already exists it will be updated with any modified 'extra' details.
        def self.create(connection, id, extra = {})
          # P4::Spec returned by 'last' subclasses Hash, merge in any extras overwriting any existing
          connection.input = connection.run(*%W(depot -o #{id})).last.merge!(extra)
          connection.run(%w(depot -i -f))
        end
      end
    end
  end
end
