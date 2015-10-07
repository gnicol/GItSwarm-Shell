# Class to manage P4 client interaction
module PerforceSwarm
  module P4
    module Spec
      class Client
        def self.create(connection, id, extra = {})
          spec = connection.run(*%W(client -o #{id})).last
          # P4::Spec returned by 'last' subclasses Hash, if we merge! in extra then
          # this bypasses the validation that would be carried out on permitted
          # fields and they would simply get ignored. Running spec[<field>] = <value>
          # causes validation to happen with P4Exception: Invalid field raised for
          # errors
          extra.each do |key, value|
            spec[key] = value
          end
          spec
        end

        def self.save(connection, spec)
          save_client(connection, false, spec)
        end

        def self.save_temp(connection, spec)
          save_client(connection, true, spec)
        end

        def self.save_client(connection, temp, spec)
          command = temp ? %w(client -x -i) : %w(client -i)
          connection.input = spec
          connection.run(*command)
        end

        def self.exists?(connection, id)
          connection.run(%w(clients)).each do |client|
            return true if client['client'].eql?(id)
          end
          false
        end

        def self.get_client(connection)
          connection.run(%w(client -o))
        end

        def self.get_client_by_id(connection, id)
          connection.run(%W(client -o #{id}))
        end
      end
    end
  end
end
