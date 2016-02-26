module PerforceSwarm
  module P4
    module Spec
      class Depot
        # given a connection and either a single depot or an array of them, this method returns either a boolean
        # true/false for the existence of a single depot or a list of depots that exist if given more than one
        def self.exists?(connection, id)
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

        # returns a hash of all depots found, keyed on depot name
        def self.all(connection)
          depots = {}
          connection.run('depots').each do |depot|
            depots[depot['name']] = depot
          end
          depots
        end

        def self.fetch(connection, id)
          # Check if the depot exists before running the depot command
          return nil unless exists?(connection, id)
          depot = connection.run(*%W(depot -o #{id})).last
          if depot['Type'] == 'stream'
            # Purposefully use merge here to get a hash object
            # so we can add to it, instead of a depot spec
            depot.merge!('numericStreamDepth' => 1)
            if depot['StreamDepth']
              # Determine the stream depth by counting the number of slashes after the depot name
              depot['numericStreamDepth'] = depot['StreamDepth'].sub(%r{^//#{depot['Name']}}, '').count('/')
            end
          end

          depot
        end

        # Create the specified depot. If the depot already exists it will be updated with any modified 'extra' details.
        def self.create(connection, id, extra = {})
          connection.input = connection.run(*%W(depot -o #{id})).last
          # P4::Spec returned by 'last' subclasses Hash, if we merge! in extra then
          # this bypasses the validation that would be carried out on permitted
          # fields and they would simply get ignored. Running spec[<field>] = <value>
          # causes validation to happen with P4Exception: Invalid field raised for
          # errors
          extra.each do |key, value|
            connection.input[key] = value
          end
          connection.run(%w(depot -i -f))
        end

        # retrieve the depot name/ID from the given depot path
        def self.id_from_path(path)
          path[%r{\A//([^/]+)/?}, 1]
        end
      end
    end
  end
end
