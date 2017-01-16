//
//  Store.swift
//  ReSwift
//
//  Created by Benjamin Encz on 11/11/15.
//  Copyright © 2015 DigiTales. All rights reserved.
//

import Foundation

/**
 This class is the default implementation of the `Store` protocol. You will use this store in most
 of your applications. You shouldn't need to implement your own store.
 You initialize the store with a reducer and an initial application state. If your app has multiple
 reducers you can combine them by initializng a `MainReducer` with all of your reducers as an
 argument.
 */
open class Store<State: StateType>: StoreType {

    // swiftlint:disable todo
    // TODO: Setter should not be public; need way for store enhancers to modify appState anyway

    /*private (set)*/ public var state: State! {
        didSet {
            subscriptions = subscriptions.filter { $0.subscriber != nil }
            subscriptions.forEach {
                // if a selector is available, subselect the relevant state
                // otherwise pass the entire state to the subscriber
                $0.newState(state: state, oldState: oldValue)
            }
        }
    }

    public var dispatchFunction: DispatchFunction!

    private var reducer: Reducer<State>

    var subscriptions: [AnySubscription] = []

    private var isDispatching = false

    public required convenience init(reducer: @escaping Reducer<State>, state: State?) {
        self.init(reducer: reducer, state: state, middleware: [])
    }

    public required init(
        reducer: @escaping Reducer<State>,
        state: State?,
        middleware: [Middleware]
    ) {
        self.reducer = reducer

        // Wrap the dispatch function with all middlewares
        self.dispatchFunction = middleware
            .reversed()
            .reduce({ [unowned self] action in
                return self._defaultDispatch(action: action)
            }) {
                [weak self] dispatchFunction, middleware in
                let getState = { self?.state }
                return middleware(self?.dispatch, getState)(dispatchFunction)
        }

        if let state = state {
            self.state = state
        } else {
            dispatch(ReSwiftInit())
        }
    }

    private func _isNewSubscriber(subscriber: AnyStoreSubscriber) -> Bool {
        let contains = subscriptions.contains(where: { $0.subscriber === subscriber })

        if contains {
            print("Store subscriber is already added, ignoring.")
            return false
        }

        return true
    }

    open func subscribe<S: StoreSubscriber>(_ subscriber: S)
        where S.StoreSubscriberStateType == State {
            subscribe(subscriber, selector: nil)
    }

    open func subscribe<SelectedState, S: StoreSubscriber>
        (_ subscriber: S, selector: ((State) -> SelectedState)?)
        where S.StoreSubscriberStateType == SelectedState {
            if !_isNewSubscriber(subscriber: subscriber) { return }

            let subscription = Subscription(subscriber: subscriber, selector: selector)
            subscriptions.append(subscription)

            if let state = self.state {
                subscription.newState(state: state, oldState: nil)
            }
    }

    open func subscribe<SelectedState: EquatableState, S: StoreSubscriber>
        (_ subscriber: S, selector: ((State) -> SelectedState)?)
        where S.StoreSubscriberStateType == SelectedState {
            if !_isNewSubscriber(subscriber: subscriber) { return }

            let subscription = EquatableSubscription(
                subscriber: subscriber,
                selector: selector
            )
            subscriptions.append(subscription)

            if let state = self.state {
                subscription.newState(state: state, oldState: nil)
            }
    }

    open func subscribe<SelectedState: EquatableState, S: StoreSubscriber>
        (_ subscriber: S, selector: ((State) -> SelectedState?)?)
        where S.StoreSubscriberStateType == SelectedState? {
            if !_isNewSubscriber(subscriber: subscriber) { return }

            let subscription = OptionalEquatableSubscription(
                subscriber: subscriber,
                selector: selector
            )
            subscriptions.append(subscription)

            if let state = self.state {
                subscription.newState(state: state, oldState: nil)
            }
    }

    open func unsubscribe(_ subscriber: AnyStoreSubscriber) {
        if let index = subscriptions.index(where: { return $0.subscriber === subscriber }) {
            subscriptions.remove(at: index)
        }
    }

    open func _defaultDispatch(action: Action) -> Void {
        guard !isDispatching else {
            raiseFatalError(
                "ReSwift:IllegalDispatchFromReducer - Reducers may not dispatch actions.")
        }

        isDispatching = true
        let newState = reducer(action, state)
        isDispatching = false

        state = newState
    }

    @discardableResult
    open func dispatch(_ action: Action) -> Void {
        dispatchFunction(action)
    }

    @discardableResult
    open func dispatch(_ actionCreatorProvider: @escaping ActionCreator) -> Void {
        if let action = actionCreatorProvider(state, self) {
            dispatch(action)
        }
    }

    open func dispatch(_ asyncActionCreatorProvider: @escaping AsyncActionCreator) {
        dispatch(asyncActionCreatorProvider, callback: nil)
    }

    open func dispatch(_ actionCreatorProvider: @escaping AsyncActionCreator,
                         callback: DispatchCallback?) {
        actionCreatorProvider(state, self) { actionProvider in
            let action = actionProvider(self.state, self)

            if let action = action {
                self.dispatch(action)
                callback?(self.state)
            }
        }
    }

    public typealias DispatchCallback = (State) -> Void

    public typealias ActionCreator = (_ state: State, _ store: Store) -> Action?

    public typealias AsyncActionCreator = (
        _ state: State,
        _ store: Store,
        _ actionCreatorCallback: @escaping ((ActionCreator) -> Void)
    ) -> Void
}

extension Store where State: EquatableState {
    open func subscribe<S: StoreSubscriber>(_ subscriber: S)
        where State: EquatableState, S.StoreSubscriberStateType == State {
            subscribe(subscriber, selector: nil)
    }
}
