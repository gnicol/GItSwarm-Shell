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

        def self.save(connection, spec, temporary_client = false)
          command = temporary_client ? %w(client -x -i) : %w(client -i)
          connection.input = spec
          connection.run(*command)
        end

        def self.exists?(connection, id)
          connection.run(%w(clients)).each do |client|
            return true if client['client'].eql?(id)
          end
          false
        end

        def self.get_client(connection, id = nil)
          connection.run(id ? %W(client -o #{id}) : %w(client -o))
        end
      end
    end
  end
end
